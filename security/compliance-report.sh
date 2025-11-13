#!/bin/bash
# =============================================================
# compliance-report.sh
# Infrastructure Assessment – Compliance Validation Script
# =============================================================

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

echo -e "\n=============================================="
echo -e "      COMPLIANCE REPORT – INFRASTRUCTURE"
echo -e "==============================================\n"

pass_count=0
fail_count=0

# Helper function
check () {
    if eval "$1" >/dev/null 2>&1; then
        echo -e "$2 : ${GREEN}PASS${NC}"
        ((pass_count++))
    else
        echo -e "$2 : ${RED}FAIL${NC}"
        ((fail_count++))
    fi
}


# =============================================================
# 1. NETWORK ISOLATION BETWEEN ENVIRONMENTS
# =============================================================

echo -e "\n1. Checking Environment Network Isolation...\n"

check "docker network inspect dev_net"           "Dev network exists"
check "docker network inspect staging_net"       "Staging network exists"
check "docker network inspect prod_net"          "Prod network exists"

check "! docker exec otc-db-dev ping -c1 gps-db-dev" \
    "Dev cannot reach Staging DB (Isolation)"

check "! docker exec otc-db-dev ping -c1 otc-db-prod" \
    "Dev cannot reach Prod DB (Isolation)"

check "! docker exec gps-db-prod ping -c1 otc-db-staging" \
    "Prod cannot reach Staging DB (Isolation)"


# =============================================================
# 2. LEGACY ARP SEGREGATION COMPLIANCE
# =============================================================

echo -e "\n2. Checking ARP Legacy Segregation...\n"

check "docker network inspect legacy_dev_net"        "Legacy Dev network exists"
check "docker network inspect legacy_staging_net"    "Legacy Staging network exists"
check "docker network inspect legacy_prod_net"       "Legacy Prod network exists"

# ARP must be unreachable from OTC/GPS
check "! docker exec otc-db-prod ping -c1 arp-db-prod" \
    "ARP PROD unreachable from OTC PROD"

check "! docker exec gps-db-dev ping -c1 arp-db-staging" \
    "ARP STAGING unreachable from GPS DEV"


# =============================================================
# 3. BASTION-ONLY ACCESS COMPLIANCE
# =============================================================

echo -e "\n3. Checking Bastion Access Controls...\n"

check "docker ps | grep bastion"     "Bastion container running"

# Direct DB access from host should fail
check "! psql -h localhost -U otc_user -c 'select 1'"  \
    "Direct DB access from host blocked"

# But bastion should be able to connect
check "docker exec bastion psql -h otc-db-dev -U otc_user -c 'SELECT 1'" \
    "Bastion can access DEV DB"


# =============================================================
# 4. AUDIT LOGGING & ACCESS TRACEABILITY
# =============================================================

echo -e "\n4. Checking Audit Logging...\n"

check "test -s security/access-audit.log" \
    "Audit log file exists and is not empty"

check "grep -q 'connected via bastion' security/access-audit.log" \
    'Audit log contains DB access entries'


# =============================================================
# 5. BACKUP VALIDATION & RETENTION
# =============================================================

echo -e "\n5. Checking Backups & Retention Policy...\n"

# Checking any backup folder exists
check "ls backups/*/*/*.sql >/dev/null 2>&1" \
    "Backups exist in expected folders"

# Check at least 1 checksum file exists
check "ls backups/*/*/checksums.sha256 >/dev/null 2>&1" \
    "Checksums exist"

# Validate checksum for latest backup
latest_checksum=$(find backups -name "checksums.sha256" | sort | tail -n1)
check "sha256sum -c $latest_checksum" \
    "Latest backup checksum valid"


# =============================================================
# 6. SECRET STORAGE & NO-PASSWORD-IN-CODE CHECK
# =============================================================

echo -e "\n6. Checking Secrets & Credential Management...\n"

check "! grep -R \"PASSWORD=\" -n docker/" \
    "No plaintext passwords in docker-compose"

check "! grep -R \"password\" -n ." \
    "No plaintext password strings in repo (allowing false positives)"


# =============================================================
# 7. PII MASKING IN QA ENVIRONMENTS
# =============================================================

echo -e "\n7. Checking PII Masking in QA...\n"

# Detect any QA DB if running
if docker ps | grep -q "qa-db"; then
    check "! docker exec qa-db psql -U qa_user -c \"SELECT email FROM users WHERE email NOT LIKE '%masked%' LIMIT 1\"" \
        "PII masking applied in QA"
else
    echo -e "${YELLOW}No QA environment active – skipping PII masking check.${NC}"
fi


# =============================================================
# 8. MIGRATION + ROLLBACK SAFETY CHECKS
# =============================================================

echo -e "\n8. Checking Migration Safeguards...\n"

check "test -f logs/migration-history.log" \
    "Migration history file exists"

check "grep -q 'ROLLBACK' logs/migration-history.log" \
    "Rollback events are recorded (if any)"


# =============================================================
# FINAL REPORT SUMMARY
# =============================================================

echo -e "\n=============================================="
echo -e " COMPLIANCE SUMMARY"
echo -e "=============================================="
echo -e " Passed Checks : ${GREEN}${pass_count}${NC}"
echo -e " Failed Checks : ${RED}${fail_count}${NC}"
echo -e "----------------------------------------------"

if [ "$fail_count" -eq 0 ]; then
    echo -e " FINAL RESULT : ${GREEN}FULLY COMPLIANT${NC}"
else
    echo -e " FINAL RESULT : ${RED}NON-COMPLIANT${NC}"
fi

echo -e "==============================================\n"
