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
- **My library**: everything already in those folders, matched on TMDB and
  sorted into Movies, TV Shows and Cartoons - the same library the Apple TV,
  iPhone, iPad and Mac apps show (see below)
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

Docker Hub is the one source of truth: the NAS never builds images, it only
pulls `artsvit/torrenttube:latest` (`docker-compose pull torrenttube && docker-compose up -d torrenttube`).

GitHub Actions (`.github/workflows/docker-publish.yml`) builds the image
(linux/amd64) and pushes it to Docker Hub on every push to `main` or
`apple-apps-and-library` that changes the server, or by hand from the Actions
tab. It needs the repository secrets `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN` (a Docker Hub access token with Read & Write).

The NAS updates itself: `nas-update.sh` (next to `docker-compose.yml` in
`/volume1/docker/torrenttube`) runs every hour from DSM Task Scheduler. It
checks playback before pulling `latest`, then recreates the container with that
image while preserving its configured folders and settings. It checks the new
image ID and waits for the app to respond before removing the old image. A
stopped container is restarted even when its image is already current. While a
film is streaming, it defers the pull until the next run. It writes what it did to
`nas-update.log` in the same folder. Set it up once in DSM: Control Panel →
Task Scheduler → Create → Scheduled Task → User-defined script; User: root;
Schedule: daily, every hour; Run command:
`/volume1/docker/torrenttube/nas-update.sh`.

After changing the updater in this repository, replace that file on the NAS
with the current `nas-update.sh`; updating the Docker image does not update a
DSM scheduled script. The scheduled command stays the same. If a recreation
fails, `nas-update.log` contains the Compose error and retains the old image.
An older image can temporarily appear as `<none>` after pulling a new `latest`
tag. This does not mean the updater built an untagged image.

By hand, from a machine with Docker:

```bash
docker login -u artsvit
docker buildx build --platform linux/amd64 -t artsvit/torrenttube:latest --push .
```

### Universal docker-compose

`docker-compose.yml` bundles Jackett so you get an out-of-the-box working setup on Linux, macOS, Windows (Docker Desktop), and Synology NAS:

```yaml
name: torrenttube

services:
  jackett:
    image: lscr.io/linuxserver/jackett:latest
    container_name: jackett
    restart: unless-stopped
    ports:
      - "9117:9117"
    volumes:
      - ./jackett-config:/config
      - ./downloads:/downloads
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Etc/UTC}

  torrenttube:
    image: artsvit/torrenttube:latest
    container_name: torrenttube
    restart: unless-stopped
    depends_on:
      - jackett
    ports:
      - "5058:5058"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - ./downloads:/downloads
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Etc/UTC}
      - TORRENTTUBE_CATEGORIES=Movies,TV Shows,Cartoon
      - JACKETTAPI_URL=http://jackett:9117
```

#### Platform configuration:
- **macOS / Windows (Docker Desktop)**: Works out of the box with default `./downloads`. Files appear in your local directory.
- **Linux**: Set `PUID` and `PGID` to match your user (run `id` in terminal, e.g. `PUID=1000 PGID=1000`).
- **Synology NAS (Container Manager)**:
  - Change `./downloads` to your media shared folder (e.g. `/volume1/homes/yourname/Media` or `/volume1/video`).
  - Set `PUID=1026` and `PGID=100` (or your DSM admin user's UID) so files aren't locked by root.

`PUID`/`PGID` control file permissions. `6881` ports are optional for BitTorrent peer incoming connections. All private keys and passwords are typed only in the Web UI, never committed to Git.

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

## My library

The **Downloads** page shows your library on the left (about three quarters
of the width) and **Downloads** and **Buffering** in a column on the right;
on a narrow screen they stack, Downloads first.

- **What it lists**: every video in the category folders (`Movies`,
  `TV Shows`, `Cartoon`), one card per title. Copies of the same film are
  merged into one card with **versions**; a series folder is one card with
  its episodes.
- **Metadata**: the server looks each title up on TMDB once (in the
  background, a few at a time) and keeps the match in
  `.torrenttube/library-metadata.json` next to your downloads - poster,
  rating, description, and whether it is a movie, TV show or cartoon. The
  page shows "Matching N new titles…" while that runs. The apps use the same
  matches.
- **Opening a title** shows its details (description, trailer, cast) and its
  files - one Play for a film, every episode in order for a series. Play
  opens the file in Infuse or VLC straight from disk: no torrent, nothing
  downloaded.
- **Search** lists matches in your library first ("In your library"), then
  the tracker's results ("Torrents"), as the apps do.
- **Settings → Library** shows how many titles there are and how many are
  matched, hides or shows the library on the Downloads page, **Refresh list**
  (look through the folders again) and **Rescan metadata** (forget every
  match and look all titles up again).
- **Download new episodes** (Settings → Library, in every app): every 30
  minutes the server finds the newest episode of each show in the library,
  searches the trackers, and downloads only the missing newer episodes into
  that show's folder. It prefers the release most like the files on disk
  (release group such as `[Hurtom]`, resolution, codec, source, audio
  languages) and, from a season pack, fetches only the needed files. What it
  fetched or tried is kept in `.torrenttube/new-episodes.json`.
- **Default audio track** (Settings → Players on the web, Playback in the
  apps): Ukrainian by default, English when a file does not have it. Other
  choices come from the languages in your library's names and your Jackett
  indexers. The apps' player and VLC playlists start with it, and new
  episodes must have it (or English).

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
   callback. Infuse 8.5 doesn't call it, so the server also watches the
   player's connections: 5 seconds after the last one closes the download
   stops, and 30 seconds after it (no new connection) the stream is
   deleted. A paused player keeps its connection open, and a seeking one
   reconnects within a second or two, so neither trips this. A stream no
   player ever connects to (the "Open in Infuse?" prompt cancelled, a
   copied link never used, a restart mid-film) is deleted after 3 minutes.
   As a last resort the server deletes a
   stream after 6 hours without any data taken. Nothing of a played film
   stays on disk: its files go with the stream, and the play link keeps
   only the magnet or tracker link and title (no .torrent copy) for 30
   days, so Infuse can resume it. `docker logs torrenttube`
   shows each player connection, disconnection and close callback.
4. Opening the same title again uses the same link, so the server simply
   starts it again, and Infuse remembers where you stopped.

While a stream exists it shows in its own **Buffering** block under Downloads (in the right-hand column) ("Waiting for the
player", "Open in the player", then "Player closed · stopped, deleting"), with ✕ to delete it now and a save
button to keep it as a download in your default folder. Download on the
same release does the same.

The **▾** beside Play (or Settings > Players > *Play opens*) picks the
player for the whole app - Infuse unless changed. A ▶ on each release row
plays that release.

**Settings > Players** shows each player's status on this device - ✓ once
it has opened from here, and for VLC on a computer its helper ✓ - with
official download links, and the helper's remove command (or, once it's
removed, its install command). The uninstaller reports back like the
installer, so the card switches by itself:

```bash
curl -fsSL "http://<server>:5058/helper/vlc-mac-uninstall.sh" | sh
```

```powershell
irm "http://<server>:5058/helper/vlc-windows-uninstall.ps1" | iex
```

If the player doesn't open within a few seconds - most likely it isn't
installed - Torrent Tube says so, with its official download links
(Infuse: App Store / firecore.com; VLC: App Store, Google Play or
videolan.org), **Try again** and **Other player**.

### VLC on a computer

VLC opens directly on iPhone, iPad and Android. Desktop VLC registers no
link a web page can open, so a Mac or Windows PC needs a small helper,
installed once. The first Play in VLC (or Settings > Players) shows a
two-step checklist: **1 VLC player** (with its official
download link) and **2 Torrent Tube helper** - one paste, as no web page
can install anything by itself: the command is copied on that tap. The
installer reports back under the page's own random key (`?k=`) that it's
done and whether it found VLC (a page can't see installed apps), and each
step turns into a ✓ by itself - or a ! with the download link if VLC is
missing. The command, without that key:

```bash
curl -fsSL http://<server>:5058/helper/vlc-mac.sh | sh
```

```powershell
irm http://<server>:5058/helper/vlc-windows.ps1 | iex
```

The helper registers a `torrenttube-vlc:` link that hands a play link to
VLC, and accepts only play links from the server it was installed from.
On a Mac it's built locally into `~/Applications` (nothing to quarantine);
on Windows it's a per-user registry entry plus a small script in
`%LOCALAPPDATA%\TorrentTube`, no administrator rights. Each script's header
says how to remove it. VLC doesn't call back when it closes, so the server
sees its connection close instead: the stream stops 5 seconds later and is
deleted 30 seconds after. A computer that isn't a Mac or Windows PC gets
**Copy link for VLC** - paste it in VLC's *File > Open Network*.

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
| `GET /api/library` | The library: `{items, metadata_pending}`. Each item has `id` (its path), `title`, `display_title`, `year`, `kind` (`movie`, `tv`, `cartoon`), `poster`, `rating`, `overview`, `tmdb_id`, `media_type`, `files`, `size` and `versions`. `?refresh=1` looks through the folders again. |
| `GET/POST /api/library/settings` | The shared Library settings: `{download_new_episodes, audio_language, audio_languages, new_episodes}`. POST changes either of the first two. |
| `DELETE /api/library/metadata` | Forgets every TMDB match; the next `GET /api/library` looks them up again. |
| `POST /api/playback/prepare` | Body `{"path": <library path>}` (or a torrent source). Returns the title's video files in play order, each with its `path`. |
| `GET /media/<path>` | A library file, straight from disk, with Range support. |
| `GET /api/intro?path=<file>` | Skip intro: `{status: "ready", start, end}` once the opening is found by comparing the episode's sound with the next one (`pending` while that runs, `none` when there is no intro). |
| `GET /api/trailer/preview/<key>` | A trailer as one stream the system player can play (Apple TV Top Shelf). |
| `DELETE /api/stream/<id>` | Stops a stream. A cached one is deleted with its data now (`deleted: true`); a download being streamed goes back to downloading normally. |

AVPlayer (Apple's native player) can't open MKV, which is what most
releases are. A native app needs a player that can (VLCKit, KSPlayer,
mpv), or the server has to remux to HLS first.

This has no authentication, like the rest of the app. Keep it on your
local network.

## Web title pages

Open a film or show to browse a dedicated page with its artwork, full description,
cast, information, and recommendations. Title links can be bookmarked and browser
Back returns to the previous title or the library.

TV shows have season controls and episode cards. Episodes on the server play in
the chosen external player; missing episodes lead to release choices. Downloads
still use the selected server folder. **Downloads & versions** keeps exact file
and quality choices together, and **Downloads & storage** returns to the existing
library and download controls. Browsing a season or missing episode does not add
a torrent by itself.

## Apple TV, iPhone, iPad and Mac apps

Native apps live in [`appletv`](appletv/README.md): Apple TV (with Top Shelf),
iPhone and iPad, and a Mac app. They share the library above, a saved
server connection, and an embedded VLC player with Skip intro and playing on
into the next episode and season. The updated server
adds episode selection, native trailer streaming, and heartbeat-based playback sessions while keeping
the web app’s external-player flow.

Continue Watching is enabled by default and shares playback positions across
Apple TV, iPhone, iPad, and Mac apps connected to the same updated server.
Existing device history is uploaded once. New positions, completed titles,
and cleared history sync through `/api/continue-watching`; offline changes
are retried when the server is available. The server stores these records in
`continue-watching.json` in its persistent state folder. Foreground apps refresh
every 30 seconds and before offering a saved playback position. Update both
the server image and the Apple apps to use this feature.

To open the Xcode project, first run `python3 appletv/scripts/bootstrap.py`.
See the Apple TV README for builds, server update requirements, and verification.

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
| `TORRENTTUBE_HOST_DOWNLOAD_DIR` | worked out on a Synology       | The downloads folder's real path on the server, for Settings (the container only sees `/downloads`) |
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
