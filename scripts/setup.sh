#!/bin/bash
# Full stack bootstrap: syncs repo, starts memory stack + Pi, then bootstraps
# dense-mem and installs Pi packages. Safe to re-run.
set -eu

echo "🔄 Syncing repo with origin..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only
else
  echo "⚠️  Not a git checkout (no .git) — skipping git pull"
fi

echo "🔄 Initializing .env and directories..."
bash scripts/init.sh

echo "🔄 Starting memory stack (memory-db, embedding, dense-mem)..."
docker compose up -d memory-db embedding dense-mem

echo "🔄 Building and starting Pi..."
docker compose up -d --build pi

echo "🔄 Bootstrapping dense-mem..."
bash scripts/memory-bootstrap.sh

echo "🔄 Installing Pi packages..."
bash scripts/install-packages.sh

echo "✅ Setup complete"