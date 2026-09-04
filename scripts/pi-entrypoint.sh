#!/bin/sh
set -u

# Git identity for commits made by the agent. Write it to the global config
# so agent preflight checks (`git config --global user.name`) see it, and set
# the env vars so commits work even from env-less contexts (bare repos, hooks).
GIT_NAME="${GIT_NAME:-vectorfield4}"
GIT_EMAIL="${GIT_EMAIL:-vectorfield4@gmail.com}"
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$GIT_NAME}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$GIT_EMAIL}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_EMAIL}"
# Never hang on an interactive credential prompt (agent has no TTY).
export GIT_TERMINAL_PROMPT=0

# If a GitHub token is present, transparently rewrite https://github.com/
# URLs to carry it, so `git push` works for any plain https: remote without
# the token appearing in `git remote -v`. Feed the same token to gh.
if [ -n "${GITHUB_TOKEN:-}" ]; then
  export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

# Force-sync declarative config from /workspace/.pi (repo bind) to the
# agent home volume. cp -f replaces the inode even when the volume already
# has the file, so a stale leftover cannot mask the repo copy. Three areas
# are mirrored; everything else in the repo is consumed by the runtime
# directly from /workspace/.pi, so duplicating it into the agent home
# would just create a second source of truth.
SRC=/workspace/.pi
DST=/root/.pi/agent
[ -f "$SRC/models.json" ] && cp -f "$SRC/models.json" "$DST/models.json"
if [ -d "$SRC/settings" ]; then
  mkdir -p "$DST/settings"
  for f in "$SRC/settings/"*.json; do
    [ -f "$f" ] && cp -f "$f" "$DST/settings/"
  done
fi
if [ -d "$SRC/agent/extensions" ]; then
  for ext_dir in "$SRC/agent/extensions"/*/; do
    [ -d "$ext_dir" ] || continue
    [ -f "$ext_dir/config.json" ] || continue
    name=$(basename "$ext_dir")
    mkdir -p "$DST/extensions/$name"
    cp -f "$ext_dir/config.json" "$DST/extensions/$name/config.json"
  done
fi

# Watchdog: restart the pi agent if its process exits (e.g. bridge fetch
# crashes the process with an uncaughtException). Container stays up, so
# Docker restart/healthcheck state stays stable and recovery takes ~seconds.

while true; do
  echo "[entrypoint] starting pi $*"
  pi --continue "$@"
  code=$?
  echo "[entrypoint] pi exited with code $code — restarting in 5s"
  sleep 5
done