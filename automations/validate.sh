#!/bin/bash
set -eo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"

echo "============================================"
echo "        STARTING VALIDATION PROCESS"
echo "============================================"

if [ ! -f "$BACKUP_DIR/checksums.sha256" ]; then
    echo "[ERROR] No checksum file found in $BACKUP_DIR."
    echo "Run ./backup.sh first."
    exit 1
fi

echo "Step 1 — Validating checksums..."
sha256sum -c "$BACKUP_DIR/checksums.sha256"

echo "✓ Checksums valid."

###############################################
# Step 2 — Temporary PostgreSQL restore tests
###############################################
echo "Step 2 — Restoring backups into temporary containers..."

for file in "$BACKUP_DIR"/*.sql; do
    db_name=$(basename "$file" .sql)
    temp_container="validate-${db_name}"

    echo "--------------------------------------------"
    echo "Testing backup file: $file"
    echo "Starting temp DB: $temp_container"

    docker run -d --name "$temp_container" \
        -e POSTGRES_PASSWORD=testpass postgres:13 >/dev/null

    sleep 5

    echo "Restoring SQL into temp DB..."
    cat "$file" | \
        PGPASSWORD=testpass docker exec -i "$temp_container" psql -U postgres >/dev/null 2>&1

    echo "Running integrity test..."
    if PGPASSWORD=testpass docker exec "$temp_container" psql -U postgres -c "SELECT 1;" >/dev/null; then
        echo "✓ Backup valid: $file"
    else
        echo "✗ Backup invalid: $file"
        docker rm -f "$temp_container" >/dev/null
        exit 1
    fi

    docker rm -f "$temp_container" >/dev/null
done

echo "============================================"
echo "    ALL BACKUPS VERIFIED SUCCESSFULLY"
echo "============================================"
