#!/bin/bash
# Inspect the pi-agent runtime: installed npm packages, extensions, processes.
# Usage: scripts/agent-stack.sh
set -euo pipefail

CT=pi-agent

echo "=== global npm packages ==="
docker exec "$CT" bash -c 'npm ls -g --depth=0 2>/dev/null || true'
echo
echo "=== pi extensions (auto-loaded from /root/.pi/agent/extensions) ==="
docker exec "$CT" bash -c '
  d=/root/.pi/agent/extensions
  if [ -d "$d" ]; then
    ls -1 "$d"
    for ext in "$d"/*/package.json; do
      [ -f "$ext" ] || continue
      name=$(basename "$(dirname "$ext")")
      ver=$(grep -m1 "\"version\"" "$ext" | sed "s/.*\"version\": *\"\([^\"]*\)\".*/\1/")
      echo "  $name @ $ver"
    done
  else
    echo "(none — no extensions dir)"
  fi
'
echo
echo "=== processes inside pi-agent ==="
docker exec "$CT" bash -c '
  ps -eo pid,ppid,etime,pcpu,comm,args 2>/dev/null \
    | head -1
  ps -eo pid,ppid,etime,pcpu,comm,args 2>/dev/null \
    | awk "NR==1 || /pi|ping-a-human|mcp|node|telegram|bridge/" \
    | grep -v "awk " || true
'
echo
echo "=== /root/.pi/agent top-level ==="
docker exec "$CT" bash -c 'ls -la /root/.pi/agent/ 2>/dev/null | head -20'
