# Torrent Tube

A tiny self-hosted web app for downloading magnet links and `.torrent` files.
Paste a magnet link or drop a `.torrent` file, watch progress live, pause/resume
or remove downloads — no accounts, no login screen.

Built on [libtorrent](https://www.libtorrent.org/) (the same BitTorrent engine
behind qBittorrent and Deluge), served by Flask + waitress.

## Features

- Paste a magnet link, search for one, or drag-and-drop / pick a `.torrent`
  file — the same input box does all three (paste a magnet to add it, type
  anything else to search)
- Search results show poster, rating and a one-click Download button when
  Jackett + TMDB are configured (see below)
- Pick which folder a download goes to (e.g. Cartoon / Movies / TV Shows)
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
docker compose up -d
```

Then open `http://localhost:5058` (or `http://<host-ip>:5058` on a NAS).

This pulls `artsvit/torrenttube:latest` from Docker Hub, same as
[Music Tube](../Music%20Tube). Until that image is pushed, comment out the
`image:` line in `docker-compose.yml` and uncomment the `build:` block instead
to build from source (see below) — that's exactly how the copy currently
running on the Synology at `192.168.0.102:5058` was deployed.

### Publishing to Docker Hub

From a machine that already has Docker (e.g. wherever `artsvit/musictube` was
built and pushed from):

```bash
docker login -u artsvit
docker build -t artsvit/torrenttube:latest .
docker push artsvit/torrenttube:latest
```

### docker-compose

```yaml
services:
  torrenttube:
    image: artsvit/torrenttube:latest
    # To build from source instead of pulling the published image, comment
    # out the `image:` line above and uncomment this:
    # build:
    #   context: .
    #   network: host  # needed on some NAS/router setups; see below
    container_name: torrenttube
    restart: unless-stopped
    ports:
      - "5058:5058"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - /volume1/homes/artsvit/Media:/downloads
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Etc/UTC
      # Must match real subfolder names under the mounted volume above.
      - TORRENTTUBE_CATEGORIES=Cartoon,Movies,TV Shows
      # Optional: enables the Search tab (see "Search" below).
      - JACKETTAPI_URL=http://192.168.0.102:9117
      - JACKETTAPI_KEY=changeme
      - JACKETTAPI_INDEXER=mazepa
      - TMDB_API_KEY=changeme
    dns:
      - 1.1.1.1
      - 8.8.8.8
```

If building on a NAS whose Docker daemon shares a host with a DNS-filtering
container (like Pi-hole), `apt-get` inside the build can hang resolving
`deb.debian.org` — the embedded Docker resolver loops back through it. The
`network: host` build option and the explicit `dns:` at runtime above route
around that; both are already set in this repo's `docker-compose.yml`.

`PUID`/`PGID` control which user ID owns the downloaded files — set these to
match your own user (`id yourname` on Linux/Synology) so files aren't owned
by root. The `6881` ports are optional but help BitTorrent peer discovery
(port forward `6881/tcp` and `6881/udp` on your router if you want faster,
more reliable transfers).

`TORRENTTUBE_CATEGORIES` is a comma-separated list of subfolders (under the
mounted volume) that show up as a destination picker in the UI. Each one is
created automatically if it doesn't already exist. Leave it unset to use the
default `Cartoon,Movies,TV Shows`, or set it to a single value to hide the
picker and always save to one folder.

## Search

The Search tab is optional and needs two other pieces, both self-hosted:

1. **[Jackett](https://github.com/Jackett/Jackett)** — does the actual tracker
   login/scraping. Run it as its own container (`lscr.io/linuxserver/jackett`),
   add your tracker (e.g. Mazepa) with **your own credentials typed directly
   into Jackett's UI** — Torrent Tube never sees or stores them — and copy
   Jackett's API key (shown top-right of its dashboard) into
   `JACKETTAPI_KEY`. `JACKETTAPI_INDEXER` is the indexer's id (`mazepa`), or
   `all` to search every indexer you've configured in Jackett.
2. **TMDB** *(optional, adds posters/ratings)* — Jackett's feed has no images,
   so this looks up each result's guessed title on
   [TMDB](https://www.themoviedb.org/settings/api) (free API key) separately.
   Titles are messy real-world tracker listings, so matching is best-effort —
   results without a match just show a plain icon instead of a poster.

Without `JACKETTAPI_URL`/`JACKETTAPI_KEY` set, the Search tab stays hidden
and the app behaves exactly like the paste-only version.

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
| `TORRENTTUBE_CATEGORIES`      | `Cartoon,Movies,TV Shows`        | Comma-separated destination subfolders shown in the UI |
| `JACKETTAPI_URL`              | unset (Search tab hidden)        | Base URL of a Jackett instance, e.g. `http://192.168.0.102:9117` |
| `JACKETTAPI_KEY`              | unset                            | Jackett's own API key (its dashboard, top right) |
| `JACKETTAPI_INDEXER`          | `all`                            | Jackett indexer id to search, or `all` |
| `TMDB_API_KEY`                | unset (no posters)               | Free key from themoviedb.org/settings/api |
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
