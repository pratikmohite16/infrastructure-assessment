#!/bin/bash
set -e

# Usage: emergency-backup.sh [container_name]
TARGET_CONTAINER="${1:-gps-db-staging}"
echo "Initiating emergency backup for container: $TARGET_CONTAINER"

# Default passwords for simulation (in real use, these should be provided)
OTC_DEV_PASS=${OTC_DEV_PASS:-otc_dev_pass}
GPS_DEV_PASS=${GPS_DEV_PASS:-gps_dev_pass}
OTC_STAGING_PASS=${OTC_STAGING_PASS:-otc_staging_pass}
GPS_STAGING_PASS=${GPS_STAGING_PASS:-gps_staging_pass}
OTC_PROD_PASS=${OTC_PROD_PASS:-otc_prod_pass}
GPS_PROD_PASS=${GPS_PROD_PASS:-gps_prod_pass}

# Show disk usage inside the DB container (for info)
docker exec "$TARGET_CONTAINER" df -h /var/lib/postgresql/data || echo "  (Warning: disk usage check failed)"
echo "Disk usage on database server (above). Proceeding with immediate backup..."

# Determine database name from container’s environment (POSTGRES_DB)
DB_NAME=$(docker exec "$TARGET_CONTAINER" printenv POSTGRES_DB)
if [ -z "$DB_NAME" ]; then
  DB_NAME="postgres"
fi

# Determine appropriate password env var for this container
name_parts=(${TARGET_CONTAINER//-/ })
if [ "${#name_parts[@]}" -ge 3 ]; then
  DB_KEY=$(echo "${name_parts[0]}" | tr '[:lower:]' '[:upper:]')
  ENV_KEY=$(echo "${name_parts[2]}" | tr '[:lower:]' '[:upper:]')
  pass_var="${DB_KEY}_${ENV_KEY}_PASS"
  DB_PASS="${!pass_var}"
fi

# Prepare backup output file
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/emergency_${name_parts[0]}_${name_parts[2]}_${TIMESTAMP}.sql.gz"

echo "Creating compressed backup: $BACKUP_FILE"
# Run pg_dump inside container, compress output on the fly to save space
docker exec -e PGPASSWORD="$DB_PASS" "$TARGET_CONTAINER" pg_dump -U postgres "$DB_NAME" | gzip > "$BACKUP_FILE"

# Verify backup success
if [ -s "$BACKUP_FILE" ]; then
  echo "Backup successful. File size: $(du -h "$BACKUP_FILE" | cut -f1)."
else
  echo "[ERROR] Backup file is empty or not created!"
fi

# Cleanup container files (simulate freeing some space by removing old WALs/logs)
echo "Freeing up space by removing old files in DB data directory..."
docker exec "$TARGET_CONTAINER" sh -c "rm -f /var/lib/postgresql/data/*.old && rm -f /var/lib/postgresql/data/*/*.old" 2>/dev/null || true

echo "Emergency backup completed. Please consider increasing storage capacity and resolving the root cause of backup failures."
