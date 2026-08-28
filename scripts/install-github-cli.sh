#!/bin/bash
# Installs GitHub CLI (gh) from GitHub's official apt repository, plus the base
# system packages the Pi container needs. Idempotent.
#
# We use GitHub's own apt repo (not Debian's `gh` package) to get current releases.
set -eu

# --- Bootstrap: slim images ship without curl; it's needed to fetch the keyring.
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl

# --- Add the GitHub CLI apt repository -------------------------------------
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list

# --- Install base packages + gh in one layer (keeps the image lean) --------
apt-get update
apt-get install -y --no-install-recommends \
  bash git ripgrep make "lftp>=4.9.2" gh
rm -rf /var/lib/apt/lists/*
