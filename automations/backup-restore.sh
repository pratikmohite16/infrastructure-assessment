#!/bin/bash
set -eo pipefail

# Directory to store backup files
BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "$BACKUP_DIR"

# Default credentials for simulation (in production, these would be provided via env or omitted entirely)
OTC_DEV_PASS=${OTC_DEV_PASS:-otc_dev_pass}
GPS_DEV_PASS=${GPS_DEV_PASS:-gps_dev_pass}
OTC_STAGING_PASS=${OTC_STAGING_PASS:-otc_staging_pass}
GPS_STAGING_PASS=${GPS_STAGING_PASS:-gps_staging_pass}
OTC_PROD_PASS=${OTC_PROD_PASS:-otc_prod_pass}
GPS_PROD_PASS=${GPS_PROD_PASS:-gps_prod_pass}
# Note: ARP passwords are intentionally not defaulted to simulate unknown credentials

ENVS=(dev staging prod)
DBS=(otc gps arp)

for env in "${ENVS[@]}"; do
  echo "Starting backup for $env environment..."
  # Parallel backup for OTC and GPS
  for db in otc gps; do
    container="${db}-db-${env}"
    backup_file="${BACKUP_DIR}/${db}_${env}_$(date +%Y%m%d%H%M%S).sql"
    echo "  Backing up ${db}-${env} to ${backup_file} ..."
    # Determine env var name for password (e.g., OTC_DEV_PASS)
    env_upper=$(echo "${env}" | tr '[:lower:]' '[:upper:]')
    db_upper=$(echo "${db}" | tr '[:lower:]' '[:upper:]')
    pass_var="${db_upper}_${env_upper}_PASS"
    # Run pg_dump inside the container, outputting to host file
    PGPASSWORD="${!pass_var}" docker exec "${container}" pg_dump -U postgres "${db}" > "${backup_file}" &
  done
  # Wait for OTC and GPS to finish
  wait
  # Backup ARP (legacy) database
  container="arp-db-${env}"
  backup_file="${BACKUP_DIR}/arp_${env}_$(date +%Y%m%d%H%M%S).sql"
  echo "  Backing up arp-${env} (legacy database) to ${backup_file} ..."
  env_upper=$(echo "${env}" | tr '[:lower:]' '[:upper:]')
  arp_pass_var="ARP_${env_upper}_PASS"
  if [ -z "${!arp_pass_var:-}" ]; then
    echo "  [WARN] Skipping ARP-${env} backup: credentials unknown."
  else
    # Attempt ARP backup if password is available
    if ! PGPASSWORD="${!arp_pass_var}" docker exec "${container}" pg_dump -U postgres "arp" > "${backup_file}"; then
      echo "  [ERROR] Backup of ARP-${env} failed. Proceeding without it."
      rm -f "${backup_file}"
    fi
  fi
  echo "Completed backup for $env."
done

# Verify and list backup files
echo "Backup files created:"
ls -l "$BACKUP_DIR"
