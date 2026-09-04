#!/bin/bash
# Diagnose memory-db (pgvector): reachability, table state, record counts.
# Read-only. Does not modify state. No secrets printed.
# Usage: scripts/diag-pgdb.sh
set -euo pipefail

CT=pi-memory-db

echo "=== reachability from pgvec-memory ==="
docker exec pi-pgvec-memory sh -c 'getent hosts memory-db && echo "memory-db resolves"' 2>&1 || echo "memory-db does not resolve from pgvec-memory"

echo
echo "=== pgvector table + counts ==="
docker exec "$CT" sh -c '
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "
    SELECT tablename FROM pg_tables WHERE schemaname=\"public\";
  " 2>&1
' 2>&1 || echo "(psql failed — see ls)"

echo
echo "=== approximate record counts per table ==="
for tbl in evidence memories meta; do
  docker exec "$CT" sh -c "
    if psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc \"SELECT 1 FROM $tbl LIMIT 1\" >/dev/null 2>&1; then
      echo \"$tbl:\"
      psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc \"SELECT COUNT(*) FROM $tbl\" 2>&1
    fi
  " 2>&1
done