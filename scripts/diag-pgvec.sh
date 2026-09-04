#!/bin/bash
# Diagnose pi-pgvec-memory: env (no secrets), logs, health, live /mcp recall.
# Read-only on disk; the /mcp recall costs one embedding call but writes nothing.
# Usage: scripts/diag-pgvec.sh
set -euo pipefail

CT=pi-pgvec-memory

echo "=== env (AI_API_* and PGVEC_*, keys masked) ==="
docker exec "$CT" sh -c '
  env \
    | grep -E "^(AI_API_URL|AI_API_EMBEDDING_MODEL|AI_API_EMBEDDING_DIMENSIONS|AI_API_KEY|PGVEC_|PGVEC_PG_)=" \
    | sed "s/\(AI_API_KEY=\)[^ ]*/\1<masked>/" \
    | sort
'

echo
echo "=== recent logs (errors, startup, fatal) ==="
docker logs "$CT" --tail 60 2>&1 | grep -iE "error|fatal|fail|503|5[0-9][0-9]|connect|listen|embed" || echo "(no matching lines)"

echo
echo "=== /health ==="
docker exec "$CT" sh -c 'wget -qO- http://localhost:8090/health 2>&1 || curl -s http://localhost:8090/health || echo "health call failed"'

echo
echo "=== /mcp tools/list (HTTP code + methods) ==="
docker exec "$CT" sh -c '
  nc_ok=0
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /tmp/mcp_list.$$ -w "http_code=%{http_code}\n" \
      -X POST http://localhost:8090/mcp \
      -H "content-type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}"
    echo "--- tools ---"
    grep -o "\"name\":\"[^\"]*\"" /tmp/mcp_list.$$ 2>/dev/null || cat /tmp/mcp_list.$$
    rm -f /tmp/mcp_list.$$
  else
    echo "curl not in container"
  fi
'

echo
echo "=== live recall (one embedding, read-only) ==="
docker exec "$CT" sh -c '
  if command -v curl >/dev/null 2>&1; then
    curl -s -w "\nhttp_code=%{http_code}\n" \
      -X POST http://localhost:8090/mcp \
      -H "content-type: application/json" \
      -H "accept: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"pgvec_recall_memory\",\"arguments\":{\"query\":\"diagnostic probe\",\"limit\":1}}}" \
      | tail -30
  else
    echo "curl not in container"
  fi
'