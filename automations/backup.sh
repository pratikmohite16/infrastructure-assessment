#!/bin/bash
set -eo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "$BACKUP_DIR"

ENVS=(dev staging prod)
DBS=(otc gps arp)

# Default passwords (simulation only)
OTC_DEV_PASS=${OTC_DEV_PASS:-otc_dev_pass}
GPS_DEV_PASS=${GPS_DEV_PASS:-gps_dev_pass}
OTC_STAGING_PASS=${OTC_STAGING_PASS:-otc_staging_pass}
GPS_STAGING_PASS=${GPS_STAGING_PASS:-gps_staging_pass}
OTC_PROD_PASS=${OTC_PROD_PASS:-otc_prod_pass}
GPS_PROD_PASS=${GPS_PROD_PASS:-gps_prod_pass}

timestamp() { date +%Y%m%d%H%M%S; }

echo "============================================"
echo "             STARTING BACKUP"
echo "============================================"

for env in "${ENVS[@]}"; do
  echo "Starting backup for $env environment..."

  for db in otc gps; do
    container="${db}-db-${env}"
    file="${BACKUP_DIR}/${db}_${env}_$(timestamp).sql"

    db_upper=$(echo "$db" | tr a-z A-Z)
    env_upper=$(echo "$env" | tr a-z A-Z)
    pass_var="${db_upper}_${env_upper}_PASS"

    echo "  Backing up ${db}-${env} → ${file}"
    PGPASSWORD="${!pass_var}" docker exec "$container" \
      pg_dump -U postgres "$db" > "$file" &
  done

  wait

  # ARP backup
  container="arp-db-${env}"
  file="${BACKUP_DIR}/arp_${env}_$(timestamp).sql"

  env_upper=$(echo "$env" | tr a-z A-Z)
  pass_var="ARP_${env_upper}_PASS"

  if [ -z "${!pass_var:-}" ]; then
    echo "  [WARN] Skipping ARP-${env} backup → password unknown"
  else
    echo "  Backing up ARP-${env} → ${file}"
    PGPASSWORD="${!pass_var}" docker exec "$container" pg_dump -U postgres arp > "$file" || rm -f "$file"
  fi

  echo "Completed backup for $env."
done

echo "Generating checksums..."
find "$BACKUP_DIR" -type f -name "*.sql" -exec sha256sum {} \; > "$BACKUP_DIR/checksums.sha256"

echo "============================================"
echo "              BACKUP COMPLETE"
echo "============================================"

ls -lh "$BACKUP_DIR"
