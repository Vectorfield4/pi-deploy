#!/bin/bash
# Idempotent manager for all pi-deploy cron jobs.
#
# Ensures exactly this set of jobs in the current user's crontab, replacing
# any previous pi-deploy blocks (old style included):
#
#   update       */2 * * * * <REPO>/scripts/update-on-push.sh >> /var/log/pi-update.log 2>&1
#   backup       0 2 * * * set -a; . <REPO>/.env; set +a; cd <REPO> && make backup
#   sessions-gc  0 3 * * * <REPO>/scripts/sessions-gc.sh --apply >> /var/log/pi-sessions-gc.log 2>&1
#
# Called automatically by `make update`, `make setup` and cloud-init — no
# manual crontab editing needed. Safe to re-run; unrelated entries are left
# untouched.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POLLER="$REPO_DIR/scripts/update-on-push.sh"
GC="$REPO_DIR/scripts/sessions-gc.sh"

# Make sure cron itself exists (Debian/Ubuntu). Best-effort for non-root.
if ! command -v crontab >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
    echo "📦 Installing cron..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cron
  else
    echo "⚠️  crontab not found and cannot auto-install (need root + apt)." >&2
    echo "   Install cron, or call the poller another way: $POLLER" >&2
    exit 1
  fi
fi

# Start/enable the cron daemon (best-effort: systemd hosts, else sysvinit).
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now cron >/dev/null 2>&1 || true
elif command -v service >/dev/null 2>&1; then
  service cron start >/dev/null 2>&1 || true
fi

# Job definitions: "<name>|<cron line>". 'update' is the update-on-push
# poller; 'backup' sources .env first because cron runs a bare environment.
JOBS=(
  "update|*/2 * * * * $POLLER >> /var/log/pi-update.log 2>&1"
  "backup|0 2 * * * set -a; . $REPO_DIR/.env; set +a; cd $REPO_DIR && make backup"
  "sessions-gc|0 3 * * * $GC --apply >> /var/log/pi-sessions-gc.log 2>&1"
)

# Rebuild the crontab: keep everything, drop any previous pi-deploy blocks
# (new `# BEGIN/END pi-deploy:<name>` style and the old unmarked backup line).
CURRENT="$(crontab -l 2>/dev/null || true)"
CURRENT="$(printf '%s' "$CURRENT" \
  | grep -vE '^# (BEGIN|END) pi-deploy:' \
  | grep -vE '^[^#].*pi-deploy && make backup' \
  | grep -vF "$POLLER" \
  | sed '/^[[:space:]]*$/d')"

BLOCK=""
for job in "${JOBS[@]}"; do
  name="${job%%|*}"
  line="${job#*|}"
  BLOCK="${BLOCK}# BEGIN pi-deploy:$name
$line
# END pi-deploy:$name
"
done

printf '%s\n%s' "$CURRENT" "$BLOCK" | crontab -

echo "✅ cron jobs installed:"
for job in "${JOBS[@]}"; do
  echo "   ${job%%|*}: ${job#*|}"
done