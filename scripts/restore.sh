#!/usr/bin/env bash
# Restore the database from a backup (like restoring an RDS snapshot).
# Usage: ./scripts/restore.sh [backups/inventory-YYYYMMDD-HHMMSS.sql.gz]   (defaults to the latest)
set -euo pipefail
cd "$(dirname "$0")/.."

file="${1:-$(ls -t backups/*.sql.gz 2>/dev/null | head -n1)}"
if [[ -z "$file" || ! -f "$file" ]]; then
  echo "No backup found. Run ./scripts/backup.sh first." >&2
  exit 1
fi

echo "Restoring $file ..."
gunzip -c "$file" | docker compose exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
echo "Restore complete."
