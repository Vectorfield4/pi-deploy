#!/bin/sh
set -u

# Watchdog: restart the pi agent if its process exits (e.g. bridge fetch
# crashes the process with an uncaughtException). Container stays up, so
# Docker restart/healthcheck state stays stable and recovery takes ~seconds.

while true; do
  echo "[entrypoint] starting pi $*"
  pi "$@"
  code=$?
  echo "[entrypoint] pi exited with code $code — restarting in 5s"
  sleep 5
done