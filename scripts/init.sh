#!/bin/bash
set -e

echo "Creating directories..."
mkdir -p workspace backups

if [ ! -f ".env" ]; then
  cp .env.example .env
  echo ".env created from .env.example — fill in your values"
else
  echo ".env already exists — skipping"
fi

echo "Initialization complete."
echo "Fill in .env, then run: make setup"
