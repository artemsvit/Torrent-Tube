#!/bin/sh
set -e

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Create/adjust a non-root user to match the PUID/PGID the host user asked
# for (Synology exposes these as "Run as" or via docker-compose env vars),
# so files written to the mounted /downloads volume are owned correctly.
# The base image already has some low-numbered groups/users, so reuse those
# by ID instead of blindly creating new ones with the same ID, which would fail.
EXISTING_GROUP="$(getent group "$PGID" | cut -d: -f1)"
if [ -z "$EXISTING_GROUP" ]; then
  addgroup --gid "$PGID" appgroup
  GROUP_NAME=appgroup
else
  GROUP_NAME="$EXISTING_GROUP"
fi

EXISTING_USER="$(getent passwd "$PUID" | cut -d: -f1)"
if [ -z "$EXISTING_USER" ]; then
  adduser --uid "$PUID" --gid "$PGID" --disabled-password --gecos "" appuser
  USER_NAME=appuser
else
  USER_NAME="$EXISTING_USER"
fi

mkdir -p "${TORRENTTUBE_DOWNLOAD_DIR:-/downloads}"
chown -R "$PUID:$PGID" "${TORRENTTUBE_DOWNLOAD_DIR:-/downloads}"

exec gosu "$USER_NAME" "$@"
