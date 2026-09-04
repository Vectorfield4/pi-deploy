#!/bin/bash
# Diagnose stack health: all containers, status, uptime, restart counts.
# Read-only. Does not modify state.
# Usage: scripts/diag-stack.sh
set -euo pipefail

echo "=== containers (status / restart count) ==="
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RestartCount}}\t{{.Image}}" 2>&1

echo
echo "=== compose project label ==="
docker ps -a --filter "label=com.docker.compose.project" \
  --format "table {{.Names}}\t{{.Status}}" 2>&1

echo
echo "=== health checks ==="
for name in pi-agent pi-pgvec-memory pi-memory-db pi-jaeger; do
  id=$(docker ps --filter "name=^/${name}$" --format '{{.ID}}')
  if [ -n "$id" ]; then
    st=$(docker inspect "$name" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' 2>/dev/null)
    fails=$(docker inspect "$name" --format '{{if .State.Health}}{{.State.Health.FailingStreak}}{{else}}0{{end}}' 2>/dev/null)
    echo "$name: health=$st failing_streak=$fails"
  else
    echo "$name: NOT RUNNING"
  fi
done