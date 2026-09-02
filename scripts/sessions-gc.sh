#!/bin/bash
# Prune dead session artefacts under /root/.pi/agent/sessions/.
#
# Always:  *.broken, *.bak (incl. __RETIRED.jsonl.bak), __RETIRED_*_scratch/ dirs.
# Age:     *.jsonl whose mtime is older than AGE_HOURS (default 24) plus its
#          sibling directory of the same name if one exists. Same sibling-dir
#          rule also fires for *.broken and *.bak files.
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
    --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$LOG")"
: >> "$LOG"

# Run inside the container with bash, not sh — /bin/sh in pi-agent is dash,
# which pathologically expands globs in heredoc argument strings before find
# sees them, so wildcards in -name are consumed before the call.
run_in() {
  docker exec "$CT" bash -c "$1"
}

# Collect candidates. Each line: <kind> <path>. kind = F (file) or D (dir).
# We use bash, single-quote the -name patterns, and pass SESSIONS_DIR + age
# via env to dodge quoting gymnastics.
CANDIDATES=$(
  SESSIONS_DIR="$SESSIONS_DIR" AGE_HOURS="$AGE_HOURS" run_in '
    set -e
    find "$SESSIONS_DIR" -type f \( -name "*.broken" -o -name "*.bak" \) 2>/dev/null \
      | grep -v "/subagent-artifacts/" \
      | awk "{print \"F \" \$0}"
    find "$SESSIONS_DIR" -maxdepth 4 -type d -name "__RETIRED_*_scratch" 2>/dev/null \
      | awk "{print \"D \" \$0}"
    find "$SESSIONS_DIR" -maxdepth 2 -type f -name "*.jsonl" -mmin +$((AGE_HOURS * 60)) 2>/dev/null \
      | awk "{print \"F \" \$0; sub(/\.jsonl\$/, \"\"); print \"D \" \$0}"
    # Sibling dirs of *.broken/*.bak when the .jsonl never opened.
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      base="${f%.broken}"; base="${base%.bak}"
      [ -d "$base" ] && echo "D $base"
    done < <(find "$SESSIONS_DIR" -type f \( -name "*.broken" -o -name "*.bak" \) 2>/dev/null | grep -v "/subagent-artifacts/")
  '
)

# Dedupe and drop the protected top-level subagent-artifacts.
ACTIONS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  p="${line#* }"
  case "$p" in
    "$SESSIONS_DIR"/subagent-artifacts) continue ;;
    "$SESSIONS_DIR"/*/subagent-artifacts) continue ;;
  esac
  ACTIONS+=("$line")
done <<< "$CANDIDATES"

ACTIONS=( $(printf '%s\n' "${ACTIONS[@]}" | sort -u) )

if [ "${#ACTIONS[@]}" -eq 0 ]; then
  echo "[$(date -Iseconds)] nothing to prune" >> "$LOG"
  exit 0
fi

# Sizes (best-effort; failures counted as 0).
TOTAL=0
for line in "${ACTIONS[@]}"; do
  p="${line#* }"
  sz=$(docker exec "$CT" bash -c "[ -e '$p' ] && ( [ -d '$p' ] && du -sb '$p' | awk '{print \$1}' || stat -c %s '$p' )" 2>/dev/null || echo 0)
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
    docker exec "$CT" bash -c "rm -rf -- '$p'" >> "$LOG" 2>&1 || true
  done
  echo "[$(date -Iseconds)] done" >> "$LOG"
else
  echo "[$(date -Iseconds)] pass --apply to remove" >> "$LOG"
fi
