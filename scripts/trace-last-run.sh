#!/usr/bin/env bash
# trace-last-run.sh — extract metrics for the most recent user task in
# the active Pi session, save to trace-logs/<id>.{json,md} in this repo.
#
# Run from the repo root on a host with ssh access to the Pi server:
#   ./scripts/trace-last-run.sh
#
# Requires: scripts/trace-last-run.js (the in-container extractor). It is
# auto-scp'd into the container under /tmp on each invocation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- config (override via env) ---
PI_HOST="${PI_HOST:-89.223.65.224}"
PI_KEY="${PI_KEY:-$HOME/.ssh/pi-deploy/pi-deploy-key}"
PI_USER="${PI_USER:-root}"
PI_DEPLOY_DIR="${PI_DEPLOY_DIR:-/root/pi-deploy}"
PI_WORKSPACE="${PI_WORKSPACE:-/root/pi-deploy/workspace}"
PI_CONTAINER="${PI_CONTAINER:-pi-agent}"

JS_SRC="${SCRIPT_DIR}/trace-last-run.js"
if [[ ! -f "${JS_SRC}" ]]; then
  echo "missing ${JS_SRC}" >&2
  exit 1
fi

# Make a per-run staging copy to avoid filename collisions
STAGE="/tmp/trace-last-run.js"
cp "${JS_SRC}" "${STAGE}"

echo "→ scp to ${PI_USER}@${PI_HOST}"
scp -i "${PI_KEY}" "${STAGE}" "${PI_USER}@${PI_HOST}:${STAGE}" >/dev/null

echo "→ docker cp into ${PI_CONTAINER}"
ssh -i "${PI_KEY}" "${PI_USER}@${PI_HOST}" "docker cp ${STAGE} ${PI_CONTAINER}:${STAGE}" >/dev/null

echo "→ running extractor in ${PI_CONTAINER}"
ssh -i "${PI_KEY}" "${PI_USER}@${PI_HOST}" \
  "cd ${PI_DEPLOY_DIR} && docker compose -f docker-compose.yml exec -T ${PI_CONTAINER} node ${STAGE}"

# Pull the latest trace files back for offline inspection
echo "→ pulling latest trace-logs/*.json back"
LATEST_JSON=$(ssh -i "${PI_KEY}" "${PI_USER}@${PI_HOST}" \
  "ls -1t ${PI_WORKSPACE}/trace-logs/*.json 2>/dev/null | head -1")
LATEST_MD=$(ssh -i "${PI_KEY}" "${PI_USER}@${PI_HOST}" \
  "ls -1t ${PI_WORKSPACE}/trace-logs/*.md 2>/dev/null | head -1")
if [[ -n "${LATEST_JSON}" ]]; then
  scp -i "${PI_KEY}" "${PI_USER}@${PI_HOST}:${LATEST_JSON}" "${REPO_ROOT}/trace-logs/" >/dev/null
  echo "  pulled $(basename "${LATEST_JSON}")"
fi
if [[ -n "${LATEST_MD}" ]]; then
  scp -i "${PI_KEY}" "${PI_USER}@${PI_HOST}:${LATEST_MD}" "${REPO_ROOT}/trace-logs/" >/dev/null
  echo "  pulled $(basename "${LATEST_MD}")"
fi
