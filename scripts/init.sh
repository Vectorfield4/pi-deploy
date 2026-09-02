#!/bin/bash
# Idempotent project init: creates directories and .env.
# - If .env missing: copies .env.example
# - If .env exists: merges keys from .env.example that are missing
# - Generates POSTGRES_PASSWORD if empty (never overwrites a set value)
set -eu

# Create required directories
mkdir -p workspace backups

# Discard local changes to tracked files so silent diffs can't break
# `git pull --ff-only` next tick. Untracked files (workspace, backups,
# .env, .pi/npm/, logs, artifacts) are left alone.
git checkout -- scripts/ AGENTS.md Makefile docker-compose.yml Dockerfile.pi .pi/ 2>/dev/null || true

# Ignore chmod-only diffs so cron-safe `+x` doesn't block future pulls.
git config core.fileMode false

# Ensure all scripts are executable; git checkout may leave them 0644
# when the repo was committed without +x bits, which silently breaks cron.
chmod +x scripts/*.sh

# Create or merge .env
if [ ! -f .env ]; then
  cp .env.example .env
  echo "✅ .env created from .env.example"
else
  # Merge: add keys from .env.example that are missing in .env
  grep -E '^[A-Z_]+=' .env.example | while IFS= read -r line; do
    key="$(printf '%s' "$line" | cut -d= -f1)"
    if ! grep -q "^${key}=" .env 2>/dev/null; then
      printf '%s\n' "$line" >> .env
      echo "✅ Added ${key} to .env"
    fi
  done
fi

# Generate POSTGRES_PASSWORD if empty/missing
if grep -q '^POSTGRES_PASSWORD=.\+' .env 2>/dev/null; then
  echo "✅ POSTGRES_PASSWORD already set"
else
  pw="$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | tr -dc 'a-f0-9' | head -c 32)"
  if grep -q '^POSTGRES_PASSWORD=' .env 2>/dev/null; then
    sed "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pw}|" .env > .env.tmp && mv .env.tmp .env
  else
    echo "POSTGRES_PASSWORD=${pw}" >> .env
  fi
  echo "✅ Generated POSTGRES_PASSWORD"
fi