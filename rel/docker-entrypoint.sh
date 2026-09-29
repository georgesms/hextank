#!/bin/sh
# Starts the app in the Docker image (see Dockerfile).
#
# Fly mounts the data volume owned by root, but the app must never run as root. So
# this script runs as root just long enough to hand the data folder to `nobody`,
# then starts the app (the command given, /app/bin/server) as `nobody`.
set -eu

if [ -n "${DATA_DIR:-}" ]; then
  mkdir -p "$DATA_DIR"
  chown -R nobody:nogroup "$DATA_DIR"
fi

exec setpriv --reuid=nobody --regid=nogroup --clear-groups "$@"
