#!/bin/bash
# Source of truth for the package list is .pi/settings.json `packages`.
# Parses it and runs `pi install` for each entry. Idempotent.
set -eu

PACKAGES="$(node -e "console.log((JSON.parse(require('fs').readFileSync('.pi/settings.json','utf8')).packages||[]).join('\n'))")"

if [ -z "$PACKAGES" ]; then
  echo "No packages in .pi/settings.json"
  exit 0
fi

COUNT="$(printf '%s\n' "$PACKAGES" | wc -l)"
echo "Installing ${COUNT} package(s)..."

for pkg in $PACKAGES; do
  echo "  pi install ${pkg}"
  docker compose exec -T pi pi install "$pkg" || exit 1
done