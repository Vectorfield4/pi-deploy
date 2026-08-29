#!/bin/bash
# Update-on-push poller: fetch repo; if upstream moved and the Pi is idle
# (no writes to /root/.pi/agent/sessions/**/*.jsonl in the last
# IDLE_AFTER_SEC seconds, default 600 = long single LLM turns included),
# apply the update. Cron entry is managed by scripts/setup-cron-jobs.sh.
set -euo pipefail

CT=pi-agent
IDLE_AFTER_SEC="${IDLE_AFTER_SEC:-600}"

# image-affecting / container-spec files -> full rebuild instead of restart
NEED_FULL_REBUILD_REGEX='^(Dockerfile.*|docker-compose.yml|Makefile|\.dockerignore|scripts/(pi-entrypoint|install-github-cli)\.sh)$'

# Single-instance lock so a long `make update` can't be re-entered.
exec 9>/tmp/pi-deploy-update.lock
flock -n 9 || { echo "update already running — skip"; exit 0; }

cd "$(dirname "$0")/.."

if ! git fetch --quiet 2>/dev/null; then
  echo "⚠️ git fetch failed (auth or network) — skip this tick"
  exit 0
fi

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u} 2>/dev/null || git rev-parse @{push} 2>/dev/null || true)

if [ -z "$REMOTE" ]; then
  echo "⚠️ no upstream tracking branch — skip"
  exit 0
fi

if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi

echo "🚀 New commits on $(git rev-parse --abbrev-ref HEAD): $LOCAL -> $REMOTE"
git log --oneline "$LOCAL..$REMOTE" | tail -n 20 | sed 's/^/    /'

# Idle gate: newest session.jsonl mtime inside the pi container.
NEWEST=$(docker exec "$CT" sh -c 'find /root/.pi/agent/sessions -maxdepth 2 -name "*.jsonl" -printf "%T@\n" 2>/dev/null | sort -rn | head -n1' 2>/dev/null || true)

if [ -n "$NEWEST" ]; then
  NEWEST_TS=${NEWEST%.*}
  AGE=$(( $(date +%s) - NEWEST_TS ))
  if [ "$AGE" -lt "$IDLE_AFTER_SEC" ]; then
    echo "⏳ Pi is busy (last session write ${AGE}s ago) — defer, retry next tick"
    exit 0
  fi
  echo "✅ Pi idle for ${AGE}s (>= ${IDLE_AFTER_SEC}s) — safe to update"
else
  echo "ℹ️ no session files found (fresh install or pi-agent down) — treating as idle"
fi

# Classify the batch: rebuild vs. install-packages+restart vs. restart.
CHANGED=$(git diff --name-only "$(git merge-base "$LOCAL" "$REMOTE")" "$REMOTE")

if printf '%s\n' "$CHANGED" | grep -qE "$NEED_FULL_REBUILD_REGEX"; then
  echo "🔧 image/container-spec changed — full rebuild via make update"
  if make update; then
    echo "✅ Pi updated to $REMOTE"
  else
    echo "❌ make update failed — will retry next tick (check git state: dirty tree? divergent commits?)"
    exit 1
  fi
elif printf '%s\n' "$CHANGED" | grep -qx '.pi/settings.json'; then
  echo "📦 package list changed — pull + install packages + restart"
  if ! docker exec "$CT" true 2>/dev/null; then
    echo "⚠️ $CT not running — cannot install packages, defer"
    exit 0
  fi
  if git pull --ff-only && make install-packages && docker compose restart pi; then
    echo "✅ Packages updated to $REMOTE"
  else
    echo "❌ package update failed — next tick will retry (check that services are healthy)"
    exit 1
  fi
else
  echo "♻️ only mounted config changed — pull + restart pi"
  if git pull --ff-only && docker compose restart pi; then
    echo "✅ Pi restarted to $REMOTE"
  else
    echo "❌ restart failed — next tick will retry"
    exit 1
  fi
fi