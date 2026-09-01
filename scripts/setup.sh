#!/bin/bash
# Full stack bootstrap: syncs repo, starts memory stack + Pi, then installs Pi
# packages. Safe to re-run.
set -eu

echo "🔄 Syncing repo with origin..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only
else
  echo "⚠️  Not a git checkout (no .git) — skipping git pull"
fi

echo "🔄 Initializing .env and directories..."
bash scripts/init.sh

echo "🔄 Building and starting memory stack (memory-db, pgvec-memory)..."
bash scripts/build-memory.sh

echo "🔄 Building and starting Pi..."
docker compose up -d --build pi

echo "🔄 Installing Pi packages..."
bash scripts/install-packages.sh

echo "🔄 Installing cron jobs (update-on-push + backup)..."
bash scripts/setup-cron-jobs.sh

echo "✅ Setup complete"