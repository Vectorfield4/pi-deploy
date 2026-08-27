#!/bin/bash
set -euo pipefail

BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -z "${POSTGRES_PASSWORD:-}" ] || [ -z "${POSTGRES_PASSWORD// }" ]; then
  echo "❌ POSTGRES_PASSWORD not set or empty in .env."
  exit 1
fi

# ── Memory backup (PostgreSQL) ──────────────────────────────────────
echo "💾 Creating memory backup (dense-mem PostgreSQL)..."
docker exec pi-memory-db sh -c \
  "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -U densemem -d densemem --no-owner" \
  > "$BACKUP_DIR/memory_$TIMESTAMP.sql"

if [ ! -s "$BACKUP_DIR/memory_$TIMESTAMP.sql" ]; then
  echo "❌ Memory backup is empty — check PostgreSQL connectivity"
  exit 1
fi
echo "  ✅ memory_$TIMESTAMP.sql"

# ── Pi sessions backup (named volume) ──────────────────────────────
echo "💾 Creating Pi sessions backup..."
docker run --rm \
  -v pi-agent-home:/source:ro \
  -v "$(cd "$BACKUP_DIR" && pwd)":/backup \
  alpine tar czf "/backup/pi-sessions_$TIMESTAMP.tar.gz" -C /source . 2>/dev/null || true

# ── Cleanup (7-day retention) ───────────────────────────────────────
find "$BACKUP_DIR" -name "memory_*.sql" -mtime +7 -delete
find "$BACKUP_DIR" -name "pi-sessions_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

echo "✅ Backup complete: $BACKUP_DIR/"
