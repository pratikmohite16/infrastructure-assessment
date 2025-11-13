#!/bin/bash
set -e

# Default to dummy credentials for simulation (in production, require env to be set)
OTC_DEV_PASS=${OTC_DEV_PASS:-otc_dev_pass}
GPS_DEV_PASS=${GPS_DEV_PASS:-gps_dev_pass}
OTC_STAGING_PASS=${OTC_STAGING_PASS:-otc_staging_pass}
GPS_STAGING_PASS=${GPS_STAGING_PASS:-gps_staging_pass}
OTC_PROD_PASS=${OTC_PROD_PASS:-otc_prod_pass}
GPS_PROD_PASS=${GPS_PROD_PASS:-gps_prod_pass}
# (No ARP defaults; simulate unknown initial ARP passwords)

# Function to generate a random 16-character alphanumeric password
generate_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

ENVS=(dev staging prod)
for env in "${ENVS[@]}"; do
  echo "Rotating credentials for $env environment..."
  # Rotate OTC and GPS DB passwords
  for db in otc gps; do
    container="${db}-db-${env}"
    if ! docker ps --format '{{.Names}}' | grep -qw "$container"; then
      echo "  [WARN] Container $container is not running, skipping."
      continue
    fi
    # Determine current password from env variable
    env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    db_upper=$(echo "$db" | tr '[:lower:]' '[:upper:]')
    pass_var="${db_upper}_${env_upper}_PASS"
    old_pass="${!pass_var}"
    if [ -z "$old_pass" ]; then
      echo "  [ERROR] No current password available for $db-$env; skipping."
      continue
    fi
    new_pass="$(generate_password)"
    # Rotate password in the database
    docker exec -e PGPASSWORD="$old_pass" "$container" \
      psql -U postgres -d postgres -c "ALTER USER postgres WITH PASSWORD '$new_pass';" >/dev/null && \
      echo "  $db-$env password rotated. New password: $new_pass (store securely)" || \
      echo "  [ERROR] Failed to rotate password for $db-$env."
  done
  # Handle ARP (legacy) password rotation/recovery
  container="arp-db-${env}"
  if docker ps --format '{{.Names}}' | grep -qw "$container"; then
    echo "  Rotating password for ARP-$env (legacy database)..."
    new_pass="$(generate_password)"
    # Attempt to reset password via local OS user access (peer authentication)
    docker exec -u postgres "$container" \
      psql -d postgres -c "ALTER USER postgres WITH PASSWORD '$new_pass';" >/dev/null && \
      echo "  ARP-$env password reset to: $new_pass (credentials recovered and rotated)" || \
      echo "  [ERROR] Could not reset password for ARP-$env (manual intervention required)."
  else
    echo "  [WARN] ARP-$env container is not running, skipping."
  fi
done

echo "Password rotation complete. Ensure all applications update their stored credentials to the new values."
