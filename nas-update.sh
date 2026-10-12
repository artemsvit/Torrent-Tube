#!/bin/sh
# Run as root from DSM Task Scheduler. Keep this file next to docker-compose.yml.
# Check playback before pulling: moving the latest tag while deferring a restart
# otherwise leaves the running container's old image displayed as <none> in DSM.
set -u
cd "$(dirname "$0")" || exit 1
DOCKER=${DOCKER:-/usr/local/bin/docker}
COMPOSE=${COMPOSE:-/usr/local/bin/docker-compose}
SERVICE=torrenttube
IMAGE=artsvit/torrenttube:latest
LOG=nas-update.log
LOCK=.nas-update.lock

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
if ! mkdir "$LOCK" 2>/dev/null; then
  log "Another update is running; skipping"
  exit 0
fi
trap 'rm -f "$LOCK/image.yml"; rmdir "$LOCK"' EXIT
trap 'exit 1' HUP INT TERM
[ ! -f "$LOG" ] || { tail -n 200 "$LOG" > "$LOCK/log" && cat "$LOCK/log" > "$LOG"; rm -f "$LOCK/log"; }

# Override only the image. The NAS compose file keeps its existing mounts,
# ports, environment, and networks, even if it still names an older image.
printf 'services:\n  %s:\n    image: %s\n' "$SERVICE" "$IMAGE" > "$LOCK/image.yml"
compose() { "$COMPOSE" -f docker-compose.yml -f "$LOCK/image.yml" "$@"; }
if ! compose config --quiet >> "$LOG" 2>&1; then
  log "Invalid compose configuration; existing container left untouched"
  exit 1
fi

running=$("$DOCKER" inspect --format '{{.Image}}' "$SERVICE" 2>/dev/null || true)
state=$("$DOCKER" inspect --format '{{.State.Running}}' "$SERVICE" 2>/dev/null || true)
if [ "$state" = true ]; then
  if ! streams=$("$DOCKER" exec "$SERVICE" python3 -c "import json, urllib.request; print(len(json.load(urllib.request.urlopen('http://127.0.0.1:5058/api/torrents', timeout=10)).get('streams', [])))" 2>> "$LOG"); then
    log "Cannot check playback; update deferred without pulling. Check container logs"
    exit 1
  fi
  case "$streams" in
    ''|*[!0-9]*) log "Invalid playback response; update deferred without pulling"; exit 1 ;;
  esac
  if [ "$streams" -gt 0 ]; then
    log "$streams film(s) streaming; update deferred without pulling"
    exit 0
  fi
fi

if ! "$DOCKER" pull "$IMAGE" >> "$LOG" 2>&1; then
  log "Image pull failed; existing container left untouched"
  exit 1
fi
latest=$("$DOCKER" image inspect --format '{{.Id}}' "$IMAGE") || exit 1
if [ -z "$latest" ]; then log "Pulled image could not be identified"; exit 1; fi
if [ "$running" = "$latest" ] && [ "$state" = true ]; then
  log "Up to date and running: $IMAGE (${latest#sha256:})"
  exit 0
fi

log "Recreating $SERVICE with $IMAGE (${latest#sha256:})"
# Never delete the old container before validating its replacement configuration.
# --no-build prevents an old build section from making an untagged local image.
if ! compose up -d --no-deps --no-build --force-recreate "$SERVICE" >> "$LOG" 2>&1; then
  log "Container recreation failed; see compose error above. Old image retained"
  exit 1
fi
actual=$("$DOCKER" inspect --format '{{.Image}}' "$SERVICE" 2>/dev/null || true)
if [ "$actual" != "$latest" ]; then
  log "Update failed: container image $actual does not match latest $latest. Old image retained"
  exit 1
fi
attempt=0
while [ "$attempt" -lt 6 ]; do
  if "$DOCKER" exec "$SERVICE" python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5058/', timeout=5).close()" >> "$LOG" 2>&1; then
    log "Updated and responding: $IMAGE (${latest#sha256:})"
    if [ -n "$running" ] && [ "$running" != "$latest" ]; then
      "$DOCKER" rmi "$running" >> "$LOG" 2>&1 || log "Old image is still in use; retained"
    fi
    exit 0
  fi
  attempt=$((attempt + 1))
  [ "$attempt" -ge 6 ] || sleep 3
done
log "New container is not responding; old image retained. Check docker logs $SERVICE"
exit 1
