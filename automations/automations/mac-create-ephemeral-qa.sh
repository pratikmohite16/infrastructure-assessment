#!/bin/bash
set -eo pipefail

echo "===================================================="
echo "        STARTING EPHEMERAL QA ENVIRONMENT"
echo "===================================================="

TTL_HOURS="${TTL_HOURS:-${1:-3}}"
TTL_SEC=$((TTL_HOURS * 3600))

# -----------------------------------
# 1. Directory Detection
# -----------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
QA_INIT_DIR="${SCRIPT_DIR}/qa_init"

mkdir -p "${QA_INIT_DIR}/otc"
mkdir -p "${QA_INIT_DIR}/gps"

echo "[INFO] Backup directory: $BACKUP_DIR"
echo "[INFO] QA init directory: $QA_INIT_DIR"

# -----------------------------------
# 2. Select Latest Backups
# -----------------------------------
OTC_BACKUP=$(ls -t "${BACKUP_DIR}"/otc_prod_*.sql 2>/dev/null | head -1)
GPS_BACKUP=$(ls -t "${BACKUP_DIR}"/gps_prod_*.sql 2>/dev/null | head -1)

if [[ -z "$OTC_BACKUP" ]]; then
  echo "[ERROR] No OTC production backup found!"
  exit 1
fi
if [[ -z "$GPS_BACKUP" ]]; then
  echo "[ERROR] No GPS production backup found!"
  exit 1
fi

echo "[INFO] Selected OTC backup: $OTC_BACKUP"
echo "[INFO] Selected GPS backup: $GPS_BACKUP"

# -----------------------------------
# 3. Prepare QA Init Folders
# -----------------------------------
rm -f "${QA_INIT_DIR}/otc/"*.sql 2>/dev/null || true
rm -f "${QA_INIT_DIR}/gps/"*.sql 2>/dev/null || true

cp "$OTC_BACKUP" "${QA_INIT_DIR}/otc/restore.sql"
cp "$GPS_BACKUP" "${QA_INIT_DIR}/gps/restore.sql"

# macOS uses native UNIX paths → no conversion needed
OTC_INIT_MOUNT="${QA_INIT_DIR}/otc"
GPS_INIT_MOUNT="${QA_INIT_DIR}/gps"

echo "[INFO] Mount path (OTC): $OTC_INIT_MOUNT"
echo "[INFO] Mount path (GPS): $GPS_INIT_MOUNT"

# -----------------------------------
# 4. Cleanup Old QA Containers
# -----------------------------------
docker rm -f otc-db-qa gps-db-qa >/dev/null 2>&1 || true
docker network rm qa_net >/dev/null 2>&1 || true

docker network create qa_net >/dev/null

# Credentials (in real case: coming from env vars)
OTC_PASS="${OTC_PROD_PASS:-otc_prod_pass}"
GPS_PASS="${GPS_PROD_PASS:-gps_prod_pass}"

# -----------------------------------
# 5. Start OTC QA DB
# -----------------------------------
echo "[INFO] Starting OTC QA DB..."
docker run -d --name otc-db-qa \
  --network qa_net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$OTC_PASS" \
  -e POSTGRES_DB=otc \
  -v "${OTC_INIT_MOUNT}:/docker-entrypoint-initdb.d" \
  postgres:13 >/dev/null

# -----------------------------------
# 6. Start GPS QA DB
# -----------------------------------
echo "[INFO] Starting GPS QA DB..."
docker run -d --name gps-db-qa \
  --network qa_net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$GPS_PASS" \
  -e POSTGRES_DB=gps \
  -v "${GPS_INIT_MOUNT}:/docker-entrypoint-initdb.d" \
  postgres:13 >/dev/null

echo "[INFO] Waiting for QA DBs to be ready..."

# -----------------------------------
# 7. Wait for Readiness
# -----------------------------------
for container in otc-db-qa gps-db-qa; do
  echo "[INFO] Checking readiness for $container..."
  for i in {1..30}; do
    if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then
      echo "  → $container is ready."
      break
    fi
    sleep 2
  done
done

# -----------------------------------
# 8. PII Sanitization
# -----------------------------------
echo "[INFO] Sanitizing PII..."

docker exec -e PGPASSWORD="$OTC_PASS" otc-db-qa psql -U postgres -d otc \
  -c "UPDATE users SET email='qa_' || id || '@example.com', ssn='XXX-XX-XXXX';" \
  >/dev/null 2>&1 || true

docker exec -e PGPASSWORD="$GPS_PASS" gps-db-qa psql -U postgres -d gps \
  -c "UPDATE users SET email='qa_' || id || '@example.com', ssn='XXX-XX-XXXX';" \
  >/dev/null 2>&1 || true

echo "[INFO] PII sanitized."

# -----------------------------------
# 9. TTL Auto-Teardown
# -----------------------------------
nohup sh -c "sleep ${TTL_SEC}; docker rm -f otc-db-qa gps-db-qa; docker network rm qa_net" >/dev/null 2>&1 &

echo "===================================================="
echo "        EPHEMERAL QA ENVIRONMENT READY"
echo "===================================================="
echo "TTL: $TTL_HOURS hour(s)"
echo "Containers: otc-db-qa, gps-db-qa"
echo "Network: qa_net"
echo "===================================================="
