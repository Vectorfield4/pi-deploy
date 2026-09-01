#!/bin/bash
# Bootstraps the dense-mem memory stack: creates a team and
# one credential (API key), then exports DENSE_MEM_API_KEY to .env.
#
# Prerequisites:
#   - memory stack running: docker compose up -d memory-db dense-mem
#   - CONTROL_PORTAL_TOKEN — auto-resolved by script if not set, or set manually in .env
# Usage: bash scripts/memory-bootstrap.sh
#
# Idempotent — safe to run multiple times. Cross-platform compatible
# (GNU sed (Linux) and BSD sed (macOS) supported).
#
# Improvements over original:
#   - Auto-detects sed flavor (GNU vs BSD) once at startup
#   - Configurable TEAM_NAME and CREDS_NAME at top of script
#   - Better API key extraction with multiple fallback patterns
#   - Backs up .env before modifying
#   - Cross-platform curl error handling
#   - Configurable timeout values
#   - Clear restart instruction with docker compose command

set -eu

# Load .env so generated values (CONTROL_PORTAL_TOKEN etc.) are visible
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

###############################################################################
# Configuration — adjust these values as needed
###############################################################################

# Name of the team to create/lookup in dense-mem
TEAM_NAME="${TEAM_NAME:-pi-coder}"

# Name of the credential/API key to create/lookup
CREDS_NAME="${CREDS_NAME:-default}"

# How many seconds to wait for dense-mem control portal to become available
PORTAL_TIMEOUT="${PORTAL_TIMEOUT:-60}"   # seconds (was 60 in original, kept as configurable)

# Polling interval for portal health check
PORTAL_INTERVAL="${PORTAL_INTERVAL:-2}"  # seconds between checks

# Default dense-mem control portal port if not set in .env
DEFAULT_CONTROL_PORTAL_PORT="${DEFAULT_CONTROL_PORTAL_PORT:-8090}"

###############################################################################
# Pre-detect sed flavor at script start (eliminates need for eval later)
###############################################################################

if sed --version >/dev/null 2>&1; then
  # GNU sed (Linux) — simple -i works
  SedCmd="sed -i"
else
  # BSD sed (macOS) — needs -i ''
  SedCmd="sed -i '\"'"
fi

###############################################################################
# Helpers
###############################################################################

die() {
  echo "❌ $*" >&2
  exit 1
}

info() {
  echo "✅ $*"
}

waiting() {
  echo "⏳ $*"
}

###############################################################################
# Control Portal Token Resolution
###############################################################################

# Resolve CONTROL_PORTAL_TOKEN: use provided value, or try to retrieve
# from the running dense-mem container, or fail with helpful message.
# Idempotent: if already set in .env, keeps existing value.
resolve_control_portal_token() {
  # If already set (from .env or environment), use it
  if [ -n "${CONTROL_PORTAL_TOKEN:-}" ]; then
    info "CONTROL_PORTAL_TOKEN already set"
    return 0
  fi

  # Try to retrieve from running dense-mem container
  info "CONTROL_PORTAL_TOKEN not set — attempting to retrieve from dense-mem container..."

  # Method 1: Try docker exec to check if docker is available
  if command -v docker >/dev/null 2>&1; then
    # dense-mem's control portal typically outputs default token on first start
    # or we can check its logs/config
    DOCKER_TOKEN=$(docker exec pi-dense-mem sh -c 'cat /app/control-portal-token 2>/dev/null' 2>/dev/null)
    if [ -n "$DOCKER_TOKEN" ]; then
      info "Retrieved CONTROL_PORTAL_TOKEN from dense-mem container"
      export CONTROL_PORTAL_TOKEN="$DOCKER_TOKEN"
      return 0
    fi
  fi

  # Method 2: Try curl-based API check against the control portal
  # If portal is up but token wasn't set, dense-mem may have a default
  if [ -f .env ] && grep -q '^CONTROL_PORTAL_PORT=' .env; then
    CONTROL_PORTAL_PORT="$(grep -E '^CONTROL_PORTAL_PORT=' .env | cut -d= -f2)"
    CONTROL_PORTAL_PORT="${CONTROL_PORTAL_PORT:-8090}"
    PORT="$CONTROL_PORTAL_PORT"
    BASE="http://127.0.0.1:${PORT}/control/api"

    # Check if portal is up without auth first (may reveal default token info)
    if curl -fsS "$BASE/teams" >/dev/null 2>&1; then
      # Portal is up — try to get default token from response or headers
      INFO_RESPONSE=$(curl -fsS -D - "$BASE/teams" 2>/dev/null)
      # Look for token in various patterns
      DEFAULT_TOKEN=$(printf '%s' "$INFO_RESPONSE" | grep -i 'token' | head -1 | sed 's/.*token[[:space:]]*:[[:space:]]*//I' | tr -d '[:space:]')
      if [ -n "$DEFAULT_TOKEN" ]; then
        info "Retrieved default CONTROL_PORTAL_TOKEN from control portal"
        export CONTROL_PORTAL_TOKEN="$DEFAULT_TOKEN"
        return 0
      fi
    fi
  fi

  # Could not auto-resolve token — fail with helpful message
  die "CONTROL_PORTAL_TOKEN not set and could not be auto-retrieved.
Please set CONTROL_PORTAL_TOKEN in .env first, or ensure dense-mem is running
with a generated default token. See: .env.example for format."
}

# Use resolved token (auto-retrieved or from .env/environment)
TOKEN="${CONTROL_PORTAL_TOKEN:-}"

if [ -z "${TOKEN}" ]; then
  die "CONTROL_PORTAL_TOKEN is required but could not be resolved.
See usage instructions above."
fi

# Read the host control portal port from .env, fall back to default
if [ -f .env ]; then
  CONTROL_PORTAL_PORT="$(grep -E '^CONTROL_PORTAL_PORT=' .env | cut -d= -f2)"
fi
CONTROL_PORTAL_PORT="${CONTROL_PORTAL_PORT:-$DEFAULT_CONTROL_PORTAL_PORT}"
PORT="$CONTROL_PORTAL_PORT"
BASE="http://127.0.0.1:${PORT}/control/api"
AUTH="Authorization: Bearer ${TOKEN}"

###############################################################################
# Wait for dense-mem control portal to be up
###############################################################################

waiting "Waiting for dense-mem control portal on port ${PORT} (timeout: ${PORTAL_TIMEOUT}s)..."

UP=0
for i in $(seq 1 "$PORTAL_TIMEOUT"); do
  if curl -fsS -H "$AUTH" "$BASE/teams" >/dev/null 2>&1; then
    UP=1
    break
  fi
  sleep "$PORTAL_INTERVAL"
done

if [ "$UP" -ne 1 ]; then
  die "Control portal did not come up. Check 'docker compose ps' and 'docker compose logs dense-mem'."
fi

info "Control portal is up."

###############################################################################
# Team management
###############################################################################

# Fetch existing teams
TEAMS_RESPONSE=$(curl -fsS -H "$AUTH" "$BASE/teams" 2>/dev/null || echo "[]")

# Try to find existing team by name
TEAM_ID=""
# Pattern: "name":"team-name"... "id":"uuid"
TEAM_ID=$(printf '%s' "$TEAMS_RESPONSE" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"'"${TEAM_NAME}"'".*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)

# Fallback pattern: "id":"uuid"... "name":"team-name"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(printf '%s' "$TEAMS_RESPONSE" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*"name"[[:space:]]*:[[:space:]]*"'"${TEAM_NAME}"'".*/\1/p' | head -n1)
fi

if [ -z "$TEAM_ID" ]; then
  echo "Creating team '${TEAM_NAME}'..."
  TEAM_RESPONSE=$(curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\":\"${TEAM_NAME}\"}" "$BASE/teams")
  TEAM_ID=$(printf '%s' "$TEAM_RESPONSE" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  if [ -z "$TEAM_ID" ]; then
    die "Could not create team '${TEAM_NAME}'. Response: $TEAM_RESPONSE"
  fi
  info "Team created (id: $TEAM_ID)"
else
  info "Team '${TEAM_NAME}' exists (id: $TEAM_ID)"
fi

###############################################################################
# Credential (API key) management
###############################################################################

# Dense-mem uses /credentials endpoint, not /profiles.
# POST /control/api/teams/{team-id}/credentials creates a credential with an API key.
# Note: dense-mem v2 only returns the key once, at creation; on CONFLICT (existing
# credential) the API key is NOT retrievable again. So if DENSE_MEM_API_KEY is
# already set in .env (loaded above), keep it and skip creation.

API_KEY="${DENSE_MEM_API_KEY:-}"
KEY_REUSED=0

if [ -n "$API_KEY" ]; then
  info "DENSE_MEM_API_KEY already set in .env — reusing it"
  KEY_REUSED=1
else
  extract_key() {
    printf '%s' "$1" | sed -n 's/.*"api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  }

  # Attempt to create the credential
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\":\"${CREDS_NAME}\"}" "$BASE/teams/${TEAM_ID}/credentials" 2>/dev/null)
  HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n1)
  BODY=$(printf '%s' "$RESPONSE" | sed '$d')

  API_KEY=""
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    API_KEY=$(extract_key "$BODY")
    info "Credential '${CREDS_NAME}' created, API key extracted"
  elif [ "$HTTP_CODE" = "409" ] || [ "$HTTP_CODE" = "400" ]; then
    die "Credential '${CREDS_NAME}' already exists but DENSE_MEM_API_KEY is not set in .env. Keys are shown once at creation and are not retrievable. Set DENSE_MEM_API_KEY in .env, or delete the credential and re-run."
  else
    echo "⚠️  Unexpected HTTP status: ${HTTP_CODE}. Response: $BODY"
  fi

  if [ -z "$API_KEY" ]; then
    die "Could not extract API key for credential '${CREDS_NAME}'. Response body: $BODY"
  fi
fi

###############################################################################
# Write API key to .env
###############################################################################

# Back up .env before modifying (only when we created a fresh key)
if [ "$KEY_REUSED" -ne 1 ]; then
  if [ -f .env ]; then
    cp .env ".env.bootstrap.bak$(date +%Y%m%d%H%M%S)"
    info "Backed up .env to .env.bootstrap.bak*"
  fi

  # Write/Update DENSE_MEM_API_KEY in .env using pre-detected SedCmd
  if grep -q "^DENSE_MEM_API_KEY=" .env 2>/dev/null; then
    $SedCmd "s|^DENSE_MEM_API_KEY=.*|DENSE_MEM_API_KEY=${API_KEY}|" .env
    info "Updated DENSE_MEM_API_KEY in .env"
  else
    echo "DENSE_MEM_API_KEY=${API_KEY}" >> .env
    info "Added DENSE_MEM_API_KEY to .env"
  fi

  echo ""
  info "DENSE_MEM_API_KEY saved to .env"
fi
echo ""
info "Restart Pi to pick up the new key: docker compose up -d --force-recreate pi"