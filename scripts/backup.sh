#!/usr/bin/env bash
# Take a logical backup of the database (like an RDS manual snapshot).
# Usage: ./scripts/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p backups
file="backups/inventory-$(date +%Y%m%d-%H%M%S).sql.gz"

# The password is read inside the container from its own environment, so it never appears on the host command line.
docker compose exec -T mysql sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --routines --triggers --databases "$MYSQL_DATABASE"' \
  | gzip > "$file"

echo "Backup written to $file ($(du -h "$file" | cut -f1))"
