#!/bin/bash
# One-shot status of the pi-deploy stack: container states, uptime, restarts.
# No sessions, no logs, no git — just "is it up, and for how long".
# Usage: scripts/status.sh
set -euo pipefail

CT=pi-agent

echo "=== containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>&1
echo
echo "=== $CT details ==="
docker inspect "$CT" \
  --format 'name:    {{.Name}}
status:  {{.State.Status}}
uptime:  {{.State.StartedAt}} ({{.State.Running}} since)
pid:     {{.State.Pid}}
restarts (host up):  host uptime below' 2>&1
echo
echo "=== host ==="
uptime
