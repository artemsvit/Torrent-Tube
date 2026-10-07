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
- Search results show poster, rating and a one-click Download button —
  Jackett (bundled) and TMDB power this, and both are configured from the
  app's own Settings screen (see below)
- Pick which folder a download goes to (e.g. Cartoon / Movies / TV Shows)
- Play a film without downloading it: **Play in Infuse / VLC** streams it to
  the app and clears it afterwards (see below)
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

Jackett is bundled as its own service, so `docker compose up -d` alone gives
you a working Search/Discover tab once you've entered a couple of API keys
(see "Search" below) — nothing else to install separately.

```yaml
services:
  jackett:
    image: lscr.io/linuxserver/jackett:latest
    container_name: jackett
    restart: unless-stopped
    ports:
      - "9117:9117"
    volumes:
      - /volume1/docker/jackett/config:/config
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Etc/UTC

  torrenttube:
    image: artsvit/torrenttube:latest
    # To build from source instead of pulling the published image, comment
    # out the `image:` line above and uncomment this:
    # build:
    #   context: .
    #   network: host  # needed on some NAS/router setups; see below
    container_name: torrenttube
    restart: unless-stopped
    depends_on:
      - jackett
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
      # Points at the bundled jackett service by its compose service name -
      # only needed if you're using an external Jackett instance instead.
      # The API keys themselves are entered from the app's own Settings
      # screen once it's running (see "Search" below), not here.
      - JACKETTAPI_URL=http://jackett:9117
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

The Search tab is optional and needs two other pieces:

1. **[Jackett](https://github.com/Jackett/Jackett)** — does the actual tracker
   login/scraping, bundled as its own service in `docker-compose.yml`. Open
   its dashboard at `http://<host-ip>:9117`, add your tracker (e.g. Mazepa)
   with **your own credentials typed directly into Jackett's UI** — Torrent
   Tube never sees or stores them — then copy Jackett's API key (shown
   top-right of its dashboard) into Torrent Tube's own Settings screen
   (**Search & Metadata → Jackett API key**). **Jackett indexer** is the
   indexer's id (e.g. `mazepa`), or `all` to search every indexer you've
   configured in Jackett.
2. **TMDB** *(optional, adds posters/ratings)* — Jackett's feed has no images,
   so this looks up each result's guessed title on
   [TMDB](https://www.themoviedb.org/settings/api) (free API key) separately.
   Paste it into **Search & Metadata → TMDB API key** in Settings. Titles are
   messy real-world tracker listings, so matching is best-effort — results
   without a match just show a plain icon instead of a poster.

Both keys are saved to `settings.json` next to your downloads (not baked
into the image or docker-compose.yml), so they survive a container restart
or redeploy. Without a Jackett URL + API key set, the Search tab stays
hidden and the app behaves exactly like the paste-only version.

## Play in Infuse / VLC

A title's details popup has a **Play in Infuse** (or **Play in VLC**)
button next to Download. One tap opens the film in that app, streamed
while it downloads, and nothing is kept afterwards:

1. Tap **Play**. Infuse opens at once with a play link
   (`/play/<token>/<title>.mkv`), and the server starts the torrent at the
   same moment - only the video file, in playback order, into a hidden
   `.stream-cache` folder under your downloads. Infuse's first request
   waits until the file list is in, then the film starts. Infuse handles
   MKV, HEVC, every audio track and subtitle, which a browser can't.
2. Pause as long as you like - the film keeps downloading and nothing is
   deleted.
3. Close the player. Infuse calls back the link it was given as
   `x-success` (`/played/<token>`), which deletes the stream and its files
   at once and brings you back to Torrent Tube. VLC on iPhone gets the same
   callback. A player that never calls back (force-quit, a dead phone, VLC
   on Android or a computer) has its stream deleted after 6 hours without
   taking any data.
4. Opening the same title again uses the same link, so the server simply
   starts it again, and Infuse remembers where you stopped.

While a stream exists it shows in its own **Buffering** block under Downloads ("Waiting for the
player", then "Open in the player"), with ✕ to delete it now and a save
button to keep it as a download in your default folder. Download on the
same release does the same.

The **▾** beside Play picks the player. The choice is saved on each
device, so a phone can use Infuse and a computer VLC. Infuse is offered on
Apple devices only. VLC opens directly on iPhone, iPad and Android; on a
computer, VLC has no link to open it, so the button copies the stream URL
for VLC's *Open Network*. A ▶ on each release row plays that release.

The phone must reach the server at the same address the page uses - on the
LAN, or over a VPN.

## Streaming API

The same streaming, for native clients (such as an Apple TV app) or any
player that opens a URL. Only the video file is fetched, in playback order,
and served over plain HTTP with Range support, so a player can start right
away and seek.

| Endpoint | What it does |
|---|---|
| `POST /api/stream` | Body `{"magnet": ...}`, `{"download_link": ...}` or `{"id": <download id>}`. Starts (or reuses) the torrent in streaming mode and returns `{id, file, name, size, url, cached, ready, progress, ...}`. A new torrent goes to the stream cache (`cached: true`); `id` streams something already in Downloads. |
| `GET /api/stream/<id>/<file>` | Buffering status: `ready` (the start is buffered), `head_progress`, `progress`, `download_rate`, `num_peers`, `done`, plus `opened` (a player has connected) and `playing` (it took data in the last 30 seconds). |
| `GET /stream/<id>/<file>/<name>` | The video itself, with HTTP Range requests (`206 Partial Content`). |
| `POST /api/play` | Body `{"token", "title", "magnet" \| "download_link" \| "id"}`. Says what a play token plays and starts it in the background. Tokens are `m-<info hash>`, `d-<download id>` or `l-<hash of the link>`. |
| `GET /played/<token>` | The player's `x-success`/`x-error` callback: stops the stream (a cached one is deleted with its files) and redirects to the app. |
| `GET /play/<token>/<name>` | The video for a play token, with Range support. Waits for the token, the torrent and its file list on the first request; starts the torrent again if its stream was deleted. |
| `POST /api/stream/<id>/keep` | Body `{"category": ...}`. Moves a cached stream to that folder and makes it a normal download. |
| `DELETE /api/stream/<id>` | Stops a stream. A cached one is deleted with its data now (`deleted: true`); a download being streamed goes back to downloading normally. |

AVPlayer (Apple's native player) can't open MKV, which is what most
releases are. A native app needs a player that can (VLCKit, KSPlayer,
mpv), or the server has to remux to HLS first.

This has no authentication, like the rest of the app. Keep it on your
local network.

## Run it locally without Docker (macOS)

```bash
./start.command
```

First run sets up a Python virtualenv automatically; subsequent runs are
instant. Downloads save to `~/Downloads/TorrentTube`.

## Configuration

Jackett/TMDB settings (URL, API keys, indexer, language) are normally set
from the app's own Settings screen once it's running - see "Search" above.
The env vars below only seed their *initial* value (handy for a from-scratch
`docker compose up`); once something's saved from Settings, that wins.

| Variable                     | Default                          | Description                   |
| ----------------------------- | --------------------------------- | ------------------------------ |
| `TORRENTTUBE_HOST`            | `127.0.0.1` (`0.0.0.0` in Docker) | Bind address                  |
| `TORRENTTUBE_PORT`            | `5058`                            | Bind port                     |
| `TORRENTTUBE_DOWNLOAD_DIR`    | `~/Downloads/TorrentTube` (`/downloads` in Docker) | Where files are saved |
| `TORRENTTUBE_CATEGORIES`      | `Cartoon,Movies,TV Shows`        | Comma-separated destination subfolders shown in the UI |
| `JACKETTAPI_URL`              | `http://jackett:9117` (the bundled service) | Base URL of a Jackett instance |
| `JACKETTAPI_KEY`              | unset                            | Jackett's own API key (its dashboard, top right) |
| `JACKETTAPI_INDEXER`          | `all`                            | Jackett indexer id to search, or `all` |
| `TMDB_API_KEY`                | unset (no posters)               | Free key from themoviedb.org/settings/api |
| `TMDB_LANGUAGE`               | `uk-UA`                          | ISO 639-1 + region for TMDB titles/overviews |
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
