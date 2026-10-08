# Torrent Tube for Apple TV, iPhone, iPad, and Mac

Native SwiftUI apps for tvOS 18, iOS/iPadOS 18 and macOS 15 or later. All targets share catalog, connection, library, favorites, history, localization, and playback-session code in `Core/`. The touch UI lives in `Mobile/` and also builds the Mac app (`TorrentTubeMac`, with Mac versions of the few iOS-only parts in `Mobile/MacSupport.swift` and its own player in `Mobile/MacPlayer.swift`); the TV UI remains in `TorrentTube/`. Only the TV targets compile the Top Shelf extension. Playback uses pinned VideoLAN TVVLCKit / MobileVLCKit / VLCKit (macOS) 3.7.2.

## Included

This is a streaming player. It has no download action, queue management, or download progress screen.

- Cinematic Home with real backdrops, title facts, and Play/Details actions.
- Horizontal shelves for New, Popular, Movies, TV Shows, Cartoons, and Ukrainian.
- Continue Watching with artwork, playback progress, and saved positions.
- Navigation: Home, Movies, TV Shows, Cartoons, Library, Search, and Settings.
- Library: what is already on the server, matched on TMDB by the server and saved on the device (details, posters, cast), one card per title with its versions.
- Playback plays on into the next episode and the next season (also across season folders); Skip intro for library episodes; Play on a series starts its first episode, and an episode click plays from the release chosen before.
- Top Shelf (Apple TV): ten new titles with kind, name, year and rating, and a trailer preview.
- Full title pages, Choose version, seasons, and episode artwork where metadata is available.
- Embedded MKV playback, Siri Remote play/pause, ten-second seeking, audio, subtitles, and Back.
- Trailer selection from the existing server metadata and fallback search, with playback inside Torrent Tube.
- Native playback leases that protect paused streams and other active viewers.

The server still fetches and buffers torrent pieces to support streaming. The web app’s download features remain separate. Authentication/pairing, synced profiles/history, and server transcoding remain future work. Apple TV supports an optional New titles Top Shelf; iPhone and iPad keep favorites and history on each device.

## Open and build

From the repository root:

```sh
python3 appletv/scripts/bootstrap.py
open appletv/TorrentTubeTV.xcodeproj
```

The bootstrap downloads the official binary and checks its pinned SHA-256. The large framework is ignored by Git. The Xcode project is checked in; XcodeGen is needed only to regenerate it after changing `project.yml`.

Select **TorrentTubeTV**, choose an Apple TV simulator or device, and run. For a physical device, select your development team in Signing & Capabilities.

The app uses `com.artsvit.torrenttube.tv`. Version is `0.1.0`, build `1`.

## Mac

```sh
python3 appletv/scripts/bootstrap.py --platform mac
xcodegen generate --spec appletv/project.yml
open appletv/TorrentTubeTV.xcodeproj
```

Select **TorrentTubeMac** and **My Mac**. The window has no title bar: Settings, Back, the tabs and the search field are in the app's own top row (⌘, ⌘[ ⌘F). The player fills the window (Space, ← →, F for full screen, Esc to close).

## iPhone and iPad

```sh
python3 appletv/scripts/bootstrap.py --platform mobile
xcodegen generate --spec appletv/project.yml
open appletv/TorrentTubeTV.xcodeproj
```

Select **TorrentTubeMobile**, then an iPhone or iPad simulator. The target supports both device families, portrait and landscape, and resizable iPad windows. For a physical device, select your development team in Signing & Capabilities and allow Local Network access when connecting to your server. No background audio entitlement is used in this first version.

- Home, Browse, Favorites, and Search use separate navigation stacks. iPad supports the system tab bar/sidebar.
- Settings opens from the gear button. Language, Continue Watching, skip interval, server refresh, and local history controls are available.
- Full-screen VLC playback supports MKV, seeking, audio, and subtitles. Backgrounding saves the position and releases this viewer's session. Reopening offers Reconnect and resume, which obtains a fresh session before the saved-position choice.
- PiP, AirPlay, downloads, and cloud synchronization are not included.

Both app targets use `com.artsvit.torrenttube.tv`, version `0.1.0`, build `1`. In App Store Connect, add the iOS platform to the same app record and upload separate iOS and tvOS archives. There is no combined iOS/tvOS binary. The suffix in the existing identifier can stay. No App Store record changes or uploads are performed by the build scripts.

The `TorrentTubeMobile` scheme includes shared model/state tests and touch UI tests. Start the isolated server shown below before UI tests. The background recovery test waits 95 seconds to exceed the server's 90-second lease. Set the Xcode build setting `TORRENTTUBE_REFERENCE_SERVER` to a LAN server address to run the optional live artwork check; it browses metadata without starting a torrent.

```sh
xcodebuild -project appletv/TorrentTubeTV.xcodeproj -scheme TorrentTubeMobile \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' \
  -collect-test-diagnostics never test
```

Keep simulator signing enabled when running TV Top Shelf tests: an unsigned app cannot access the app-group container. Device signing and App Store distribution require your Apple development team.

## Server update

Deploy the root `app.py`, `playback_sessions.py`, and `trailer_streams.py`, or rebuild the Docker image, which includes them and the trailer dependencies. Use your existing settings and downloads volume.

The native app can browse older servers. It disables playback until `/api/config` advertises `file_selection` and `playback_sessions`. The NAS observed during development still runs the older server; it was not redeployed by this change.

New endpoints include `GET /api/episodes?id=<series-id>&season=<number>` for episode names, artwork, and runtime. It uses the server’s TMDB key and language, caches results, and keeps service credentials on the server. The player matches explicit `S01E02` or `1x02` filenames to metadata. Unknown or ambiguous names stay visible for manual selection.

Playback endpoints:

| Endpoint | Purpose |
| --- | --- |
| `POST /api/playback/prepare` | Resolve the source and list video files. Body uses `id`, `magnet`, or `download_link`. |
| `POST /api/playback/sessions` | Start a selected file and register a viewer. Same source fields plus integer `file`. Returns a media URL and opaque `session`. |
| `POST /api/playback/sessions/<session>` | Renew the lease and get buffering status. Send every 20 seconds, including while paused. |
| `DELETE /api/playback/sessions/<session>` | Close only this viewer. A cached stream is deleted when no native viewers or legacy sockets remain. |

Leases expire after 90 seconds without a heartbeat. Existing web-player callbacks and socket cleanup remain in use. They cannot delete a stream while a native lease is active. A deliberate torrent removal still applies to the torrent itself.

Use a LAN HTTP address or trusted HTTPS. API and media URLs preserve a reverse-proxy path prefix. This version does not support a browser-based proxy login or server accounts. Jackett and TMDB credentials remain on the server and are not fetched by the app.

## Apple TV Home banner

Home features up to four titles, mixing recent films, TV shows, and cartoons. The newest catalog matches take priority over each category's first result. Repeated title IDs are excluded. Previous/next buttons and page indicators let the viewer switch banners while keeping remote focus.

The Trailer button plays the preview inside the hero using the existing VLC trailer stream API. Play still starts the main film or episode. Previews begin muted, with an explicit sound button and Stop preview action. The still artwork remains until video is ready and returns after the preview ends or fails.

Autoplay Home trailers is enabled by default and can be turned off under Settings → Home. It waits five seconds while the banner's controls have focus. It is disabled automatically for Reduce Motion and VoiceOver. Leaving the banner, opening another screen, entering background, or starting the main film cancels preparation and stops the preview. Previews create no movie session and do not alter Continue Watching.

## Apple TV Top Shelf

The optional New titles shelf uses a native full-screen carousel with up to four landscape banners. It adds no section heading or metadata overlay. tvOS provides the Dock, page indicators, and More Info button. More Info opens the selected title directly.

The app saves banner artwork in its shared app-group container. The extension only reads the snapshot and image URLs. Failed image requests can retain a cached banner; the brand image is the fallback when no banner is available.

Servers advertising `capabilities.top_shelf_previews` provide a stable `GET /api/trailer/preview/<youtube-key>` URL. It resolves a single H.264/AAC MP4 and redirects with HTTP 307 to the existing Range-capable relay. Provider links renew before expiry. No trailer video files are saved. The app warms these URLs with HEAD requests. Unavailable previews keep the still-banner experience. Existing VLC trailer playback retains its separate video/audio support.

Deploy the updated `app.py` and `trailer_streams.py` before enabling native Top Shelf previews on the NAS. Older servers continue to show the banners. tvOS owns the focus delay and trailer playback; the API does not expose an exact five-second timer.

## Native trailer support

The existing server returns YouTube IDs through `/api/details` and `/api/trailer`. The app preserves that list and its language order. Selecting a trailer calls `POST /api/trailer/stream` with its `key`. The new server resolves a playable stream and returns URLs under `/trailer-stream/<token>/<resource>`.

The server relays the video and audio from the provider. It forwards Range requests, rewrites HLS playlists with relative resource paths, and restricts upstream URLs and redirects to HTTPS Google Video hosts. Separate video/audio sources are played together by the embedded VLC engine. No trailer media file is saved, and no torrent/download item is created. Metadata tokens expire after 30 minutes.

Docker includes Node.js 22 and the pinned tools from `trailer-requirements.txt`. For a local server, install the tools separately using Python 3.10 or later, and make Node.js 22 or later available on PATH. For example, with the installed Homebrew Python:

```sh
python3.13 -m venv .trailer-tools
.trailer-tools/bin/pip install -r trailer-requirements.txt
export TORRENTTUBE_YTDLP="$PWD/.trailer-tools/bin/yt-dlp"
venv/bin/python app.py
```

This keeps the existing server/libtorrent environment intact. Update the pinned resolver when provider changes require it. Some videos may be restricted or have no playable stream; the app reports this and lets the viewer choose another trailer. [Resolver documentation](https://github.com/yt-dlp/yt-dlp), [JavaScript runtime requirements](https://github.com/yt-dlp/yt-dlp/wiki/EJS).

## Verify

Server regression tests use temporary local files and real libtorrent:

```sh
venv/bin/python -m unittest discover -s tests -v
```

For the native UI/playback test, start this isolated server in one terminal. It needs `ffmpeg`, Flask, libtorrent, and waitress:

```sh
venv/bin/python appletv/scripts/smoke_server.py
```

Then run the **TorrentTubeTV** test scheme against an Apple TV simulator. The scheme points the UI test at `http://127.0.0.1:5069`. The test selects an episode, plays generated MKV media, pauses for 35 seconds, resumes, closes, and reopens at the saved position. The default fixture also serves generated footage for trailer tests. Add `--live-trailers` and set `TORRENTTUBE_YTDLP` to test the real public trailer source. Stop the fixture server after testing; its files are temporary.

Xcode 27’s optional simulator diagnostic collector stalled after testing. The final CLI run completed with `-collect-test-diagnostics never`, which keeps all test cases enabled.

Development validation on 8 October 2026:

- Apple TV device and simulator builds passed with Xcode 27.
- Fifteen Python server tests passed, including session protection, Range seeking, episode metadata caching, trailer input validation, relay ranges, playlist rewriting, and expiry.
- Eight native model/API tests passed, including safe episode matching and compatibility with existing saved positions.
- UI checks passed across the completed runs: connection, Change server, streaming-only title navigation, real NAS browsing, 35-second pause/seek/resume, poster focus restoration, Cartoons navigation, dark focused TV Shows icon, and in-app trailer playback.
- Home, Details, and Cartoons were rendered with real NAS artwork. Movie playback used generated MKV media. The official English Last of Us trailer played through the live provider resolver inside Torrent Tube, with its English audio track visible. The Ukrainian trailer returned no playable provider stream.
- Screenshots are saved locally under `build/evidence/streaming-design/` and `build/evidence/trailers-cartoons/`.
- The simulator still reports one UIKit `_UIReplicantView` warning during a view transition. The navigation checks passed; recheck on a physical Apple TV.
- Physical Apple TV, incomplete-torrent playback, HDR/Dolby Vision, multichannel audio, and embedded subtitle variants still need device tests. No signed archive or App Store submission was produced.

The NAS has not been redeployed. Its current server supports catalog/details browsing, but needs the updated root server files and trailer dependencies for native movie/trailer playback and episode artwork.

## Dependency

The pinned artifact is VideoLAN’s official `TVVLCKit-3.7.2-3e42ae47-79128878.tar.xz`, with SHA-256:

```
fa264c2eb17d648669d9d12b51e76e5b6769828354517d09b340387b30825f58
```

Its license text is included in the app under Settings → Player licenses. The upstream source and licensing details are at [VideoLAN VLCKit](https://github.com/videolan/vlckit). Check the exact distribution obligations before shipping a public release.

## Top Shelf and preferences

Settings now uses three sections with remote-friendly rows:

- **Home & Top Shelf:** choose the dark brand banner or New titles, show/hide Continue Watching without deleting positions, and turn browsing previews on/off.
- **Playback:** choose a 10-, 15-, or 30-second skip interval and open player licenses.
- **Server & Storage:** change the server, refresh the catalog, or clear this server's local viewing history after confirmation.

To use Top Shelf, place Torrent Tube in the first row of the Apple TV Home screen. Select **Settings → Home & Top Shelf → Top Shelf → New titles**. The app shares up to 12 recent catalog titles with its native TV Services extension. Selecting a poster opens that title's details. The snapshot updates when the app opens, returns to the foreground, or refreshes its catalog. With no cached titles, or with Brand artwork selected, tvOS uses the static banner. New titles requires catalog search and poster metadata from the server.

The app and extension both use the App Group `group.com.artsvit.torrenttube.tv`. For a physical-device build, enable this group for both bundle identifiers in your Apple developer account and regenerate their provisioning profiles. The extension bundle identifier is `com.artsvit.torrenttube.tv.topshelf`. Simulator builds use local signing.

Static shelf images remain reproducible from `scripts/render_brand.swift`, with standard and wide assets at 1x and 2x. The logo and app icon keep their established mark.
