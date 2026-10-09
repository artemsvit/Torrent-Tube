#!/bin/sh
# Keeps the NAS on the image Docker Hub has. Docker Hub is the one source of
# truth: GitHub Actions publishes artsvit/torrenttube:latest, and this script
# (run every hour by DSM Task Scheduler, as root) pulls it when it changed and
# recreates the container - but never while a film is streaming; then it
# tries again next hour. The image it replaced is deleted, so only one stays.
#
# Lives next to docker-compose.yml: /volume1/docker/torrenttube/nas-update.sh
set -u
cd "$(dirname "$0")" || exit 1
DOCKER=${DOCKER:-/usr/local/bin/docker}
COMPOSE=${COMPOSE:-/usr/local/bin/docker-compose}
SERVICE=torrenttube
IMAGE=artsvit/torrenttube:latest
LOG=nas-update.log

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
[ -f "$LOG" ] && tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

running=$($DOCKER inspect --format '{{.Image}}' "$SERVICE" 2>/dev/null)
if ! $DOCKER pull -q "$IMAGE" > /dev/null 2>&1; then
  log "Docker Hub could not be reached; trying again next time"
  exit 1
fi
latest=$($DOCKER image inspect --format '{{.Id}}' "$IMAGE")
if [ "$running" = "$latest" ]; then
  log "Up to date"
  exit 0
fi

# Films playing in Infuse/VLC right now; a restart would cut them off.
streams=$($DOCKER exec "$SERVICE" python3 -c "import json, urllib.request; print(len(json.load(urllib.request.urlopen('http://127.0.0.1:5058/api/torrents', timeout=10)).get('streams', [])))" 2>/dev/null || echo 0)
if [ "${streams:-0}" -gt 0 ]; then
  log "New image waiting: $streams film(s) streaming; trying again next time"
  exit 0
fi

if $COMPOSE up -d "$SERVICE" > /dev/null 2>&1; then
  log "Updated to ${latest#sha256:}"
  [ -n "$running" ] && $DOCKER rmi "$running" > /dev/null 2>&1
else
  log "docker-compose up failed"
  exit 1
fi
