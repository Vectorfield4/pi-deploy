#!/bin/bash
# Diagnose seed + runtime of pi-agent: cwd, seeded config, tools, sessions, logs.
# Read-only. Does not modify state.
# Usage: scripts/diag-agent.sh
set -euo pipefail

CT=pi-agent

echo "=== process / working dir ==="
docker exec "$CT" sh -c 'pgrep -x pi >/dev/null && echo "pi: running" || echo "pi: NOT running"'
docker exec "$CT" pwd 2>/dev/null || true

echo
echo "=== /etc/pi-skel exists? (seed source bind) ==="
docker exec "$CT" sh -c 'ls -la /etc/pi-skel 2>&1 | head -20'

echo
echo "=== /root/.pi/agent top-level ==="
docker exec "$CT" sh -c 'ls -la /root/.pi/agent/ 2>&1 | head -25'

echo
echo "=== settings.json: defaultTools + packages (no secrets) ==="
docker exec "$CT" sh -c '
  if [ -f /root/.pi/agent/settings.json ]; then
    node -e "
      const s=require(String.raw\`/root/.pi/agent/settings.json\`);
      console.log(\"defaultTools:\", JSON.stringify(s.defaultTools));
      console.log(\"defaultModel:\", s.defaultModel);
      console.log(\"packages:\", (s.packages||[]).join(\", \"));
    "
  else
    echo "settings.json MISSING — main runs on a bare model prompt"
  fi
'

echo
echo "=== SYSTEM.md present? (router prompt) ==="
docker exec "$CT" sh -c 'ls -la /root/.pi/agent/SYSTEM.md 2>&1 && head -5 /root/.pi/agent/SYSTEM.md 2>&1'

echo
echo "=== recent agent logs (startup, errors, MCP 503) ==="
docker logs "$CT" --tail 80 2>&1 | grep -iE "error|fail|503|mcp|started|welcome|entrypoint" || echo "(no matching lines)"