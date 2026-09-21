# Torrent Tube

A tiny self-hosted web app for downloading magnet links and `.torrent` files.
Paste a magnet link or drop a `.torrent` file, watch progress live, pause/resume
or remove downloads — no accounts, no login screen.

Built on [libtorrent](https://www.libtorrent.org/) (the same BitTorrent engine
behind qBittorrent and Deluge), served by Flask + waitress.

## Features

- Paste a magnet link, or drag-and-drop / pick a `.torrent` file
- Live progress, download/upload speed, peer count and ETA
- Pause, resume, and remove (optionally deleting the downloaded files)
- Downloads survive a container restart (queue is saved to disk)
- Light/dark theme, responsive down to phone width
- No accounts, no tracking, no ads — it's just yours

**No login screen by design.** This app is meant to sit on your own LAN. If
you ever expose it to the internet, put it behind your Synology's own
reverse-proxy authentication or a VPN — don't port-forward it directly.

## Run it with Docker (recommended)

```bash
docker compose up -d --build
```

Then open `http://localhost:5058` (or `http://<host-ip>:5058` on a NAS).
Downloads land in the `./downloads` folder next to `docker-compose.yml`
(mount whatever path you want on your Synology instead).

### docker-compose

```yaml
services:
  torrenttube:
    build: .
    container_name: torrenttube
    restart: unless-stopped
    ports:
      - "5058:5058"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - /volume1/downloads:/downloads
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Etc/UTC
```

`PUID`/`PGID` control which user ID owns the downloaded files — set these to
match your own user (`id yourname` on Linux/Synology) so files aren't owned
by root. The `6881` ports are optional but help BitTorrent peer discovery
(port forward `6881/tcp` and `6881/udp` on your router if you want faster,
more reliable transfers).

## Run it locally without Docker (macOS)

```bash
./start.command
```

First run sets up a Python virtualenv automatically; subsequent runs are
instant. Downloads save to `~/Downloads/TorrentTube`.

## Configuration (env vars)

| Variable                     | Default                          | Description                   |
| ----------------------------- | --------------------------------- | ------------------------------ |
| `TORRENTTUBE_HOST`            | `127.0.0.1` (`0.0.0.0` in Docker) | Bind address                  |
| `TORRENTTUBE_PORT`            | `5058`                            | Bind port                     |
| `TORRENTTUBE_DOWNLOAD_DIR`    | `~/Downloads/TorrentTube` (`/downloads` in Docker) | Where files are saved |
| `PUID` / `PGID`               | `1000` / `1000`                  | Docker only — file ownership  |

## Notes

- Only download content you have the right to download (your own files,
  Linux distributions, public-domain media, or otherwise permitted use).
- The queue (magnet links / torrent metadata) is saved under
  `<download-dir>/.torrenttube/torrents.json` so it survives restarts;
  partially-downloaded files themselves are never deleted unless you choose
  "delete files" when removing a torrent.

## License

MIT
