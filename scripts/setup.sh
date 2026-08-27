#!/bin/bash
# Full stack bootstrap: starts memory stack + Pi, then bootstraps dense-mem
# and installs Pi packages. Safe to re-run.
set -eu

echo "🔄 Starting memory stack (memory-db, embedding, dense-mem)..."
docker compose up -d memory-db embedding dense-mem

echo "🔄 Building and starting Pi..."
docker compose up -d --build pi

echo "🔄 Bootstrapping dense-mem..."
bash scripts/memory-bootstrap.sh

echo "🔄 Installing Pi packages..."
bash scripts/install-packages.sh

echo "✅ Setup complete"