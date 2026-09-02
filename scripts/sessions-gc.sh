#!/bin/bash
# Prune dead session artefacts under /root/.pi/agent/sessions/.
#
# Always:  *.broken, *.bak (incl. __RETIRED.jsonl.bak), __RETIRED_*_scratch/ dirs.
# Age:     *.jsonl whose mtime is older than AGE_HOURS (default 24) plus its
#          sibling directory of the same name if one exists.
# Idempotent. Dry-run by default; --apply to actually remove.
# Cron entry is managed by scripts/setup-cron-jobs.sh.
set -euo pipefail

CT=pi-agent
SESSIONS_DIR=/root/.pi/agent/sessions
AGE_HOURS="${AGE_HOURS:-24}"
APPLY=0
LOG=/var/log/pi-sessions-gc.log

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --help|-h) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$LOG")"
: >> "$LOG"

# Run inside the container if it's up, else on the host path so GC still works
# during a restart. The named volume mountpoint matches SESSIONS_DIR.
if docker exec "$CT" true 2>/dev/null; then
  IN_CT=1
else
  IN_CT=1 # host path == container path for the named volume; run shell directly
  echo "[$(date -Iseconds)] $CT exec probe failed; using host path" >> "$LOG"
fi

# Collect candidates. Each line: <kind> <path>. kind = F (file) or D (dir).
CANDIDATES=$(
  if [ "$IN_CT" = 1 ]; then
    docker exec "$CT" sh -c "
      set -e
      # broken + bak: any depth under sessions, but exclude the shared top-level.
      find '$SESSIONS_DIR' -type f \( -name '*.broken' -o -name '*.bak' \) 2>/dev/null \
        | grep -v '/subagent-artifacts/' \
        | awk '{print \"F \" \$0}'
      # scratch dirs from retired sessions.
      find '$SESSIONS_DIR' -maxdepth 4 -type d -name '__RETIRED_*_scratch' 2>/dev/null \
        | awk '{print \"D \" \$0}'
      # old jsonl + their sibling dirs.
      find '$SESSIONS_DIR' -maxdepth 2 -type f -name '*.jsonl' -mmin +$((AGE_HOURS * 60)) 2>/dev/null \
        | awk '{print \"F \" \$0; sub(/\.jsonl\$/, \"\"); print \"D \" \$0}'
    "
  fi
)

# Dedupe and drop the protected top-level subagent-artifacts.
ACTIONS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  p="${line#* }"
  case "$p" in
    $SESSIONS_DIR/subagent-artifacts) continue ;;
    $SESSIONS_DIR/*/subagent-artifacts) continue ;;
  esac
  ACTIONS+=("$line")
done <<< "$CANDIDATES"

# Dedupe.
ACTIONS=( $(printf '%s\n' "${ACTIONS[@]}" | sort -u) )

if [ "${#ACTIONS[@]}" -eq 0 ]; then
  echo "[$(date -Iseconds)] nothing to prune" >> "$LOG"
  exit 0
fi

# Sizes (best-effort; failures counted as 0).
TOTAL=0
for line in "${ACTIONS[@]}"; do
  p="${line#* }"
  if [ "$IN_CT" = 1 ]; then
    sz=$(docker exec "$CT" sh -c "[ -e '$p' ] && du -sb '$p' 2>/dev/null | awk '{print \$1}' || stat -c %s '$p' 2>/dev/null" 2>/dev/null || echo 0)
  fi
  TOTAL=$((TOTAL + ${sz:-0}))
done

MODE="DRY-RUN"; [ "$APPLY" -eq 1 ] && MODE="APPLY"
echo "[$(date -Iseconds)] $MODE: ${#ACTIONS[@]} entries, ~${TOTAL} bytes" >> "$LOG"
for line in "${ACTIONS[@]}"; do
  echo "  $line" >> "$LOG"
done

if [ "$APPLY" -eq 1 ]; then
  for line in "${ACTIONS[@]}"; do
    p="${line#* }"
    docker exec "$CT" rm -rf -- "$p" >> "$LOG" 2>&1 || true
  done
  echo "[$(date -Iseconds)] done" >> "$LOG"
else
  echo "[$(date -Iseconds)] pass --apply to remove" >> "$LOG"
fi
