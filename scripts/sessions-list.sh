#!/bin/bash
# List pi session files inside pi-agent with mtime/size/type tags.
# Type: live (mtime < AGE_HOURS), dead (older .jsonl), broken (.broken),
#       bak (.bak, incl. __RETIRED.jsonl.bak), retired (__RETIRED_*_scratch dir).
# Usage:
#   scripts/sessions-list.sh              # top 20 by mtime
#   scripts/sessions-list.sh --all        # full list
#   scripts/sessions-list.sh --live       # only live
#   scripts/sessions-list.sh --dead       # dead, broken, bak, retired
#   scripts/sessions-list.sh --summary    # counts + total size per type
set -euo pipefail

CT=pi-agent
SESSIONS_DIR=/root/.pi/agent/sessions
AGE_HOURS="${AGE_HOURS:-24}"
LIMIT=20
FILTER=all
SUMMARY=0

for arg in "$@"; do
  case "$arg" in
    --all) LIMIT=999999 ;;
    --live) FILTER=live ;;
    --dead) FILTER=dead ;;
    --summary) SUMMARY=1; LIMIT=0 ;;
    --help|-h) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# Emit TSV: kind<TAB>name<TAB>size_bytes<TAB>mtime_epoch.
# All $-vars in the docker block are escaped (\$) so my host shell does not
# interpolate them — the inner bash sees $f, $d, $base, etc. literally.
ROWS=$(
  docker exec "$CT" bash -c '
    set -e
    cd "$1/--workspace--" 2>/dev/null || exit 0
    shift
    now=$(date +%s)
    cutoff=$(( now - $1 * 3600 ))
    # Live + dead: top-level .jsonl.
    for f in *.jsonl; do
      [ -e "$f" ] || continue
      mt=$(stat -c %Y "$f")
      sz=$(stat -c %s "$f")
      kind=live; [ "$mt" -lt "$cutoff" ] && kind=dead
      printf "%s\t%s\t%s\t%s\n" "$kind" "$f" "$sz" "$mt"
    done
    # Broken + bak.
    for f in *.jsonl.broken *.jsonl.bak; do
      [ -e "$f" ] || continue
      mt=$(stat -c %Y "$f"); sz=$(stat -c %s "$f")
      case "$f" in
        *.broken) kind=broken ;;
        *) kind=bak ;;
      esac
      printf "%s\t%s\t%s\t%s\n" "$kind" "$f" "$sz" "$mt"
    done
    # Retired scratch dirs. Strip trailing / before case-match (bash * in
    # case does not cross /).
    for d in */; do
      base="${d%/}"
      case "$base" in
        *__RETIRED_scratch)
          mt=$(stat -c %Y "$d"); sz=$(du -sb "$d" 2>/dev/null | awk "{print \$1}")
          printf "retired\t%s\t%s\t%s\n" "$d" "${sz:-0}" "$mt" ;;
      esac
    done
  ' _ "$SESSIONS_DIR" "$AGE_HOURS"
)

if [ "$SUMMARY" -eq 1 ]; then
  echo "=== summary (age cutoff ${AGE_HOURS}h) ==="
  printf '%s\n' "$ROWS" | awk -F'\t' '
    { c[$1]++; b[$1]+=$3 }
    END {
      printf "%-10s %8s %12s\n", "type", "count", "bytes"
      for (k in c) printf "%-10s %8d %12d\n", k, c[k], b[k]
    }' | sort -k2 -rn
  echo
  echo "=== top 5 by size ==="
  printf '%s\n' "$ROWS" | awk -F'\t' '{ printf "%12d  %s\n", $3, $2 }' | sort -rn | head -5
  exit 0
fi

if [ -z "$ROWS" ]; then
  echo "(no sessions)"
  exit 0
fi

# Apply live/dead filter.
case "$FILTER" in
  live) ROWS=$(printf '%s\n' "$ROWS" | awk -F'\t' '$1=="live"') ;;
  dead) ROWS=$(printf '%s\n' "$ROWS" | awk -F'\t' '$1!="live"') ;;
esac

# Sort by mtime desc, humanize, format.
printf '%s\n' "$ROWS" | sort -t$'\t' -k4 -rn | head -n "$LIMIT" | awk -F'\t' '
  function human(s) {
    if (s >= 1073741824) return sprintf("%.1fG", s/1073741824)
    if (s >= 1048576)    return sprintf("%.1fM", s/1048576)
    if (s >= 1024)       return sprintf("%.1fK", s/1024)
    return sprintf("%dB", s)
  }
  {
    cmd = "date -d @" $4 " +%Y-%m-%dT%H:%M:%S"
    cmd | getline ts; close(cmd)
    printf "%-9s %-20s %8s  %s\n", $1, ts, human($3), $2
  }'
