#!/bin/bash
set -e

# Ephemeral QA environment creation script
TTL_HOURS="${TTL_HOURS:-${1:-3}}"
TTL_SEC=$(( TTL_HOURS * 3600 ))

# Ensure backup directory exists
BACKUP_DIR="${BACKUP_DIR:-./backups}"
if [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup directory not found: $BACKUP_DIR"
  exit 1
fi

# Find latest production backup files for OTC and GPS
OTC_BACKUP=$(ls -t "$BACKUP_DIR"/otc_prod_*.sql 2>/dev/null | head -1)
GPS_BACKUP=$(ls -t "$BACKUP_DIR"/gps_prod_*.sql 2>/dev/null | head -1)
if [ -z "$OTC_BACKUP" ] || [ -z "$GPS_BACKUP" ]; then
  echo "Error: Latest prod backup files not found for OTC/GPS."
  exit 1
fi

# Use production credentials for QA (for simulation simplicity)
OTC_PROD_PASS=${OTC_PROD_PASS:-otc_prod_pass}
GPS_PROD_PASS=${GPS_PROD_PASS:-gps_prod_pass}

echo "Spinning up ephemeral QA environment from production backups..."
# Create an isolated network for QA if it doesn't exist
docker network inspect qa_net >/dev/null 2>&1 || docker network create --label ephemeral=qa qa_net

# Remove any existing QA containers (cleanup from previous runs)
docker rm -f otc-db-qa gps-db-qa 2>/dev/null || true

# Launch QA DB containers, mounting backup SQLs for automatic restore
docker run -d --name otc-db-qa --network qa_net --label env=qa --label ephemeral=qa \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD="${OTC_PROD_PASS}" -e POSTGRES_DB=otc \
  -v "$(realpath "$OTC_BACKUP")":/docker-entrypoint-initdb.d/restore.sql:ro \
  postgres:13

docker run -d --name gps-db-qa --network qa_net --label env=qa --label ephemeral=qa \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD="${GPS_PROD_PASS}" -e POSTGRES_DB=gps \
  -v "$(realpath "$GPS_BACKUP")":/docker-entrypoint-initdb.d/restore.sql:ro \
  postgres:13

# Wait for the QA databases to finish initialization
echo "Waiting for QA databases to be ready..."
for c in otc-db-qa gps-db-qa; do
  for i in {1..30}; do
    docker exec "$c" pg_isready -U postgres -d "${c%%-db-qa}" && break
    sleep 2
  done
done

# Sanitize sensitive data (PII) in the QA databases
echo "Sanitizing sensitive data in QA databases..."
docker exec -e PGPASSWORD="${OTC_PROD_PASS}" otc-db-qa psql -U postgres -d otc \
  -c "UPDATE users SET email=CONCAT('redacted_', id, '@example.com'), ssn='XXX-XX-XXXX';"
docker exec -e PGPASSWORD="${GPS_PROD_PASS}" gps-db-qa psql -U postgres -d gps \
  -c "UPDATE users SET email=CONCAT('redacted_', id, '@example.com'), ssn='XXX-XX-XXXX';"

echo "Ephemeral QA environment is up. It will be auto-terminated after ${TTL_HOURS} hour(s)."

# Schedule auto-teardown of the QA environment
nohup sh -c "sleep ${TTL_SEC}; docker rm -f otc-db-qa gps-db-qa; docker network rm qa_net" >/dev/null 2>&1 &

# Estimate cost for running this environment
HOURLY_RATE=0.10  # assumed $0.10 per DB/hour
cost=$(echo "$HOURLY_RATE * 2 * $TTL_HOURS" | bc)
printf "Estimated cost for running QA environment for %d hour(s): \$%.2f\n" "$TTL_HOURS" "$cost"
