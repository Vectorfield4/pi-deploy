#!/bin/bash
# Bootstraps the dense-mem memory stack: creates a team and
# one credential (API key), then exports DENSE_MEM_API_KEY to .env.
#
# Prerequisites:
#   - .env filled in with CONTROL_PORTAL_TOKEN
#   - memory stack running: docker compose up -d memory-db embedding dense-mem
#
# Usage: bash scripts/memory-bootstrap.sh
#
# Idempotent — safe to run multiple times.

set -eu

if [ -z "${CONTROL_PORTAL_TOKEN:-}" ]; then
  echo "❌ CONTROL_PORTAL_TOKEN not set in .env. Fill in .env first."
  exit 1
fi

TOKEN="$CONTROL_PORTAL_TOKEN"
PORT="${CONTROL_PORTAL_PORT:-8090}"
BASE="http://127.0.0.1:${PORT}/control/api"
AUTH="Authorization: Bearer ${TOKEN}"

echo "⏳ Waiting for dense-mem control portal on port ${PORT}..."
UP=0
for i in $(seq 1 60); do
  if curl -fsS -H "$AUTH" "$BASE/teams" >/dev/null 2>&1; then
    UP=1
    break
  fi
  sleep 2
done
if [ "$UP" -ne 1 ]; then
  echo "❌ Control portal did not come up. Check 'docker compose ps' and 'docker compose logs dense-mem'."
  exit 1
fi
echo "✅ Control portal is up."

# --- Team ---
TEAM_ID=""
TEAMS_RESPONSE=$(curl -fsS -H "$AUTH" "$BASE/teams" 2>/dev/null || echo "[]")

# Try to find existing team "pi-coder" by name
TEAM_ID=$(printf '%s' "$TEAMS_RESPONSE" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"pi-coder".*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)

if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(printf '%s' "$TEAMS_RESPONSE" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*"name"[[:space:]]*:[[:space:]]*"pi-coder".*/\1/p' | head -n1)
fi

if [ -z "$TEAM_ID" ]; then
  echo "Creating team 'pi-coder'..."
  TEAM_RESPONSE=$(curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d '{"name":"pi-coder"}' "$BASE/teams")
  TEAM_ID=$(printf '%s' "$TEAM_RESPONSE" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  if [ -z "$TEAM_ID" ]; then
    echo "❌ Could not create team 'pi-coder'."
    echo "   Response: $TEAM_RESPONSE"
    exit 1
  fi
  echo "✅ Team created (id: $TEAM_ID)"
else
  echo "✅ Team 'pi-coder' exists (id: $TEAM_ID)"
fi

# --- Credential (API key) ---
# Dense-mem uses /credentials endpoint, not /profiles.
# POST /control/api/teams/{team-id}/credentials creates a credential with an API key.
extract_key() {
  printf '%s' "$1" | sed -n 's/.*"api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name":"default"}' "$BASE/teams/$TEAM_ID/credentials" 2>/dev/null)
HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

API_KEY=""
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  API_KEY=$(extract_key "$BODY")
elif [ "$HTTP_CODE" = "409" ] || [ "$HTTP_CODE" = "400" ]; then
  echo "Credential 'default' exists, fetching key..."
  CREDENTIALS=$(curl -fsS -H "$AUTH" "$BASE/teams/$TEAM_ID/credentials" 2>/dev/null || echo "[]")
  API_KEY=$(printf '%s' "$CREDENTIALS" | tr '\n' ' ' | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"default"[^}]*"api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi

if [ -z "$API_KEY" ]; then
  echo "❌ Could not extract API key."
  echo "   Response: $BODY"
  exit 1
fi

# Write to .env
if grep -q "^DENSE_MEM_API_KEY=" .env 2>/dev/null; then
  sed -i "s|^DENSE_MEM_API_KEY=.*|DENSE_MEM_API_KEY=${API_KEY}|" .env
else
  echo "DENSE_MEM_API_KEY=${API_KEY}" >> .env
fi

echo "✅ DENSE_MEM_API_KEY saved to .env"
echo ""
echo "Restart Pi to pick up the new key: docker compose up -d --force-recreate pi"
