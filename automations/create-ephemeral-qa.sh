#!/bin/bash
set -eo pipefail

echo "===================================================="
echo "        STARTING EPHEMERAL QA ENVIRONMENT"
echo "===================================================="

TTL_HOURS="${TTL_HOURS:-${1:-3}}"
TTL_SEC=$((TTL_HOURS * 3600))

# -----------------------------------
# 1. Directory detection
# -----------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
QA_INIT_DIR="$SCRIPT_DIR/qa_init"

mkdir -p "$QA_INIT_DIR/otc"
mkdir -p "$QA_INIT_DIR/gps"

echo "[INFO] Backup directory: $BACKUP_DIR"
echo "[INFO] QA init directory: $QA_INIT_DIR"

# -----------------------------------
# 2. Select latest production backups
# -----------------------------------
OTC_BACKUP=$(ls -t "$BACKUP_DIR"/otc_prod_*.sql 2>/dev/null | head -1)
GPS_BACKUP=$(ls -t "$BACKUP_DIR"/gps_prod_*.sql 2>/dev/null | head -1)

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
# 3. Prepare QA init folders
# -----------------------------------
rm -f "$QA_INIT_DIR/otc/"*.sql
rm -f "$QA_INIT_DIR/gps/"*.sql

cp "$OTC_BACKUP" "$QA_INIT_DIR/otc/restore.sql"
cp "$GPS_BACKUP" "$QA_INIT_DIR/gps/restore.sql"

# -----------------------------------
# 4. Use WSL path directly (NO Windows conversion)
# -----------------------------------
convert_path() {
  echo "$1"
}

OTC_INIT_MOUNT=$(convert_path "$QA_INIT_DIR/otc")
GPS_INIT_MOUNT=$(convert_path "$QA_INIT_DIR/gps")

echo "[INFO] Docker mount path (OTC): $OTC_INIT_MOUNT"
echo "[INFO] Docker mount path (GPS): $GPS_INIT_MOUNT"

# -----------------------------------
# 5. Cleanup previous QA containers
# -----------------------------------
docker rm -f otc-db-qa gps-db-qa >/dev/null 2>&1 || true
docker network rm qa_net >/dev/null 2>&1 || true

docker network create qa_net >/dev/null

# Credentials
OTC_PASS="otc_prod_pass"
GPS_PASS="gps_prod_pass"

# -----------------------------------
# 6. Start OTC QA DB
# -----------------------------------
echo "[INFO] Starting OTC QA DB..."
docker run -d --name otc-db-qa \
  --network qa_net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$OTC_PASS" \
  -e POSTGRES_DB=otc \
  -v "$OTC_INIT_MOUNT:/docker-entrypoint-initdb.d" \
  postgres:13 >/dev/null

# -----------------------------------
# 7. Start GPS QA DB
# -----------------------------------
echo "[INFO] Starting GPS QA DB..."
docker run -d --name gps-db-qa \
  --network qa_net \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD="$GPS_PASS" \
  -e POSTGRES_DB=gps \
  -v "$GPS_INIT_MOUNT:/docker-entrypoint-initdb.d" \
  postgres:13 >/dev/null

echo "[INFO] DBs started. Waiting for readiness..."

# -----------------------------------
# 8. Wait for readiness
# -----------------------------------
for c in otc-db-qa gps-db-qa; do
  echo "[INFO] Checking readiness for $c..."
  for i in {1..30}; do
    if docker exec "$c" pg_isready -U postgres >/dev/null 2>&1; then
      echo "  -> $c is ready."
      break
    fi
    sleep 2
  done
done

# -----------------------------------
# 9. Sanitize PII
# -----------------------------------
echo "[INFO] Sanitizing PII..."

docker exec -e PGPASSWORD="$OTC_PASS" otc-db-qa \
  psql -U postgres -d otc \
  -c "UPDATE users SET email='qa_' || id || '@example.com', ssn='XXX-XX-XXXX';" \
  >/dev/null 2>&1 || true

docker exec -e PGPASSWORD="$GPS_PASS" gps-db-qa \
  psql -U postgres -d gps \
  -c "UPDATE users SET email='qa_' || id || '@example.com', ssn='XXX-XX-XXXX';" \
  >/dev/null 2>&1 || true

echo "[INFO] PII sanitized."

# -----------------------------------
# 10. TTL Auto Teardown
# -----------------------------------
nohup sh -c "sleep ${TTL_SEC}; docker rm -f otc-db-qa gps-db-qa; docker network rm qa_net" >/dev/null 2>&1 &

echo "===================================================="
echo "          QA ENVIRONMENT READY"
echo "===================================================="
echo "TTL: ${TTL_HOURS} hours"
echo "Containers: otc-db-qa, gps-db-qa"
echo "Network: qa_net"
echo "===================================================="
