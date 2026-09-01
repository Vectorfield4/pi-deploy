#!/bin/bash
# Builds the pgvec-memory Docker image on this machine and brings the memory
# stack + Pi up in docker compose. Safe to re-run; idempotent.
set -eu

echo "🔄 Building memory image (pgvec-memory)..."
docker compose build pgvec-memory

echo "🔄 Bringing up memory stack (memory-db, pgvec-memory)..."
docker compose up -d memory-db pgvec-memory

echo "🔄 Restarting Pi against the fresh stack..."
docker compose up -d --force-recreate pi

echo "✅ Memory stack status:"
docker compose ps --format '{{.Name}}\t{{.State}}\t{{.Status}}' memory-db pgvec-memory pi
