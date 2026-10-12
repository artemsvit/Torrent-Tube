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

DOWNLOAD_PATH="${TORRENTTUBE_DOWNLOAD_DIR:-/downloads}"
STATE_PATH="${TORRENTTUBE_STATE_DIR:-$DOWNLOAD_PATH/.torrenttube}"

# Never walk the media library at startup. On a NAS that can take minutes
# or hours, and it changes ownership of unrelated files in a shared folder.
# Only the app's directories and its own state files need ownership setup.
for APP_PATH in "$DOWNLOAD_PATH" "$STATE_PATH"; do
  echo "Checking app directory: $APP_PATH"
  mkdir -p "$APP_PATH"
  if ! gosu "$USER_NAME" test -w "$APP_PATH"; then
    chown "$PUID:$PGID" "$APP_PATH"
  fi
  if ! gosu "$USER_NAME" test -w "$APP_PATH"; then
    echo "Startup failed: $APP_PATH is not writable by UID $PUID / GID $PGID. Check NAS folder permissions." >&2
    exit 1
  fi
done
# Saved settings and SQLite files from an older root-run container belong
# to the app. Limit repair to this directory, never downloaded media.
find "$STATE_PATH" -maxdepth 1 -type f ! -uid "$PUID" -exec chown "$PUID:$PGID" {} +
echo "Starting Torrent Tube as UID $PUID / GID $PGID"

exec gosu "$USER_NAME" "$@"
