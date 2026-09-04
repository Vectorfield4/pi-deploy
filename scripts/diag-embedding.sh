#!/bin/bash
# Diagnose the external embedding API (AI_API_URL) from inside pgvec-memory.
# Read-only: dumps env (key masked) and does a basic TCP/health probe.
# Does NOT send a real /embeddings request (costs a token + sends the key).
# Usage: scripts/diag-embedding.sh
set -euo pipefail

CT=pi-pgvec-memory

echo "=== embedding endpoint config (key masked) ==="
docker exec "$CT" sh -c '
  echo "AI_API_URL=$AI_API_URL"
  echo "AI_API_EMBEDDING_MODEL=$AI_API_EMBEDDING_MODEL"
  echo "AI_API_EMBEDDING_DIMENSIONS=$AI_API_EMBEDDING_DIMENSIONS"
  echo "AI_API_KEY=<masked>"
'

echo
echo "=== where does AI_API_URL point? (host / scheme extraction) ==="
docker exec "$CT" sh -c '
  url="$AI_API_URL"
  host="${url#*//}"; host="${host%%/*}"
  echo "host:port = $host"
  echo "warning: 127.0.0.1/localhost inside container hits the container, not the host."
'

echo
echo "=== TCP reachability to embedding host (no app call) ==="
docker exec "$CT" sh -c '
  url="$AI_API_URL"
  target="${url#*//}"; target="${target%%/*}"
  if echo "$target" | grep -q ":"; then
    h=${target%%:*}; p=${target##*:}
    (echo >/dev/tcp/$h/$p) >/dev/null 2>&1 && echo "tcp $h:$p OPEN" || echo "tcp $h:$p CLOSED/unreachable"
  else
    echo "no port in target, cannot TCP-probe"
  fi
'