FROM node:22-bookworm-slim AS trailer-js
FROM debian:bookworm-slim
COPY --from=trailer-js /usr/local/bin/node /usr/local/bin/node

# python3-libtorrent is Debian's prebuilt binding for the same libtorrent
# engine qBittorrent/Deluge use — installing it from apt (rather than pip)
# means no compiler toolchain and native packages for both amd64 and arm64,
# which keeps this image small and lets it run on Synology out of the box.
# gosu: lets the container start as root (to fix volume permissions) then
# drop down to a normal PUID/PGID before running the app — standard practice
# for NAS containers (Synology, Unraid, etc.) so downloaded files are owned
# by your own user, not root.
# ca-certificates: without it Python's SSL context has no trusted root
# store, so any https:// call (TMDB search enrichment, torrent files served
# over https) fails with CERTIFICATE_VERIFY_FAILED.
# libchromaprint-tools: fpcalc, the sound fingerprints "Skip intro" compares.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 python3-venv python3-libtorrent python3-flask python3-waitress gosu curl ca-certificates libstdc++6 \
       libchromaprint-tools \
    && rm -rf /var/lib/apt/lists/*

COPY trailer-requirements.txt /tmp/trailer-requirements.txt
RUN python3 -m venv /opt/trailer-tools \
    && /opt/trailer-tools/bin/pip install --no-cache-dir -r /tmp/trailer-requirements.txt
ENV TORRENTTUBE_YTDLP=/opt/trailer-tools/bin/yt-dlp

WORKDIR /app

COPY app.py .
COPY playback_sessions.py .
COPY media_library.py .
COPY trailer_streams.py .
COPY intro_detection.py .
COPY episodes.py .
COPY templates/ templates/
COPY static/ static/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV TORRENTTUBE_HOST=0.0.0.0 \
    TORRENTTUBE_PORT=5058 \
    TORRENTTUBE_DOWNLOAD_DIR=/downloads \
    PUID=1000 \
    PGID=1000

VOLUME ["/downloads"]
EXPOSE 5058 6881 6881/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD curl -f http://127.0.0.1:5058/ || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["python3", "app.py"]
