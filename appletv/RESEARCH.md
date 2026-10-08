# Torrent Tube for Apple TV

Research date: 7 October 2026. Scope: repository inspection and current primary documentation. No live server or Apple TV playback was tested.

**Recommendation:** build a native SwiftUI tvOS app in this folder. Reuse the Flask server’s JSON APIs and HTTP streaming. Keep torrents, downloads, Jackett, and TMDB on the server. Embed a playback engine in the app, with controls designed for the Siri Remote.

## Connection and app flow

1. Show **Connect to Torrent Tube**, a **Server address** field, and **Connect**. Example: `http://192.168.0.102:5058`. Use the system keyboard; save the address after successful validation.
2. Request `/api/config`. Validate the JSON shape, rather than accepting any HTTP 200 response. Show clear errors for an unreachable server, wrong service, unsupported server, or authentication requirement.
3. Open the native catalog. On later launches, reconnect automatically and offer **Change server** if connection fails.
4. Open a title, choose a release or episode, then play inside Torrent Tube. Return to the same focused item when playback closes.

This is a connection screen initially: the server currently has no accounts or authentication. Actual login requires new server authentication. A later pairing code can authorize the TV, with its credential stored in Keychain.

The interface is bundled in the tvOS app. The server supplies data, not HTML screens. Send `X-TorrentTube-Client: tvos` and app version for diagnostics and capability negotiation. This identifies the client but is not authentication. Do not rely on User-Agent sniffing to choose the UI.

Apple recommends SwiftUI for new tvOS content apps and has deprecated TVMLKit. [Apple migration guidance](https://developer.apple.com/videos/play/wwdc2024/10207/)

## What we can reuse

| Existing API | Apple TV use |
| --- | --- |
| `GET /api/config` | Connection check, categories, feature availability |
| `/api/discover/feeds`, `/api/discover`, `POST /api/discover/enrich` | Catalog shelves; load metadata for visible items |
| `/api/search`, `/api/details` | Search, title details, release selection |
| `/api/torrents` and pause/resume routes | Downloads and progress |
| `POST /api/stream` | Start playback; returns a relative media URL |
| `GET /api/stream/<id>/<file>` | Buffering status |
| `/stream/<id>/<file>/<name>` | Media bytes with HTTP Range support for seeking |
| Stream keep/delete routes | Keep a download or close temporary playback |

Source: `app.py`. `/` always renders the existing web page. The server has no HLS conversion, playback history, or client session API. Resolve media URLs against the saved server base URL, including any reverse-proxy path prefix.

## Embedded player choice

“Our own player” should mean playback inside our app, with our UI. Building a codec engine from scratch would add substantial work.

| Option | Assessment |
| --- | --- |
| **TVVLCKit** | First prototype choice. VideoLAN provides a tvOS library for broad media playback. Build our remote controls around it. Verify hardware decoding, tracks, subtitles, and current device/simulator packaging. |
| **AVPlayer + AVKit** | Best system playback integration for supported media. The current raw MKV path needs another engine or a conversion layer. HLS remuxing changes the container without re-encoding; incompatible codecs still require transcoding. |
| **KSPlayer** | Alternative with AVPlayer/FFmpeg integration. Its current README lists GPL licensing, a paid LGPL option, and packaging differences. Do not assume a free, unrestricted tvOS dependency. |

Sources: [VideoLAN VLCKit](https://github.com/videolan/vlckit), [Apple AVKit](https://developer.apple.com/documentation/avkit/playing-video-content-in-a-standard-user-interface), [KSPlayer licensing and features](https://github.com/kingslay/KSPlayer).

Select the engine only after real Apple TV tests. Library feature lists do not prove Dolby Vision, HDR, Atmos, or smooth 4K playback for our files. Review the exact bundled library licenses before distribution.

## TV interface

Use **Discover · Search · Downloads · Settings**, with a Continue Watching shelf once history exists. Hide unavailable server features. Build poster shelves, readable text, spacious layouts, visible focus, and simple directional navigation. Keep important controls inside safe areas and restore focus after navigation. Support VoiceOver and reduced motion. These choices follow [Apple’s tvOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/).

Use a full title screen with artwork, summary, Play/Resume, releases, and episodes. The player needs play/pause, seeking, audio/subtitle selection, buffering feedback, and predictable Back behavior. Follow familiar [Apple playback conventions](https://developer.apple.com/design/human-interface-guidelines/playing-video).

## Server changes needed

- **Version and capabilities:** add a stable server identity/API version and flags for file selection, sessions, and history. Keep older clients working.
- **Episode selection:** expose torrent video files and accept a file index. `pick_video_file()` currently chooses the largest video; it cannot select an episode.
- **Playback sessions:** add client-owned sessions, heartbeat, explicit close, and expiry. Current socket-based cleanup stops a cached torrent after 5 seconds without connections and deletes it after 30 seconds. A fully buffered or paused embedded player may have no open socket. Track multiple viewers so one closing cannot delete another’s stream. Preserve existing web-player cleanup behavior.
- **Resume history:** initially save position locally, keyed by server, torrent, and file. Add server sync later. Existing play tokens preserve links, not playback positions.
- **Connection policy:** support local HTTP with a scoped ATS configuration; use trusted HTTPS for remote access. Apple documents `NSAllowsLocalNetworking` for local names/IP addresses. tvOS currently has no local-network privacy prompt, according to [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). [ATS setting](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- **Authentication:** remote access needs a defined API/media authentication method. Browser proxy login is not automatically usable by a native player. Avoid fetching `/api/settings` for onboarding: it returns service secrets.
- **Trailers:** existing YouTube iframe playback is web-specific. Leave trailers out of the first version until a supported tvOS route is confirmed.

## Implementation sequence

1. Create the tvOS target and connection screen. Build the API client and a minimal Downloads view.
2. Prototype TVVLCKit against permitted sample media and the real server. Test completed and incomplete files, seeking, long pauses, tracks, subtitles, and 4K before selecting the engine.
3. Add file selection and playback sessions on the server. Verify two simultaneous viewers, disconnects, restart recovery, and cache cleanup.
4. Build Discover, Search, title details, release/episode selection, and local resume history. Verify every path with the Siri Remote on a physical Apple TV.
5. Prepare distribution after reviewing dependencies and content access. Apple’s guideline 5.2.3 makes unauthorized media downloading/file sharing a material App Store risk; moving torrents to the server does not itself establish eligibility. Provide a review-accessible server with permitted sample content. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

The first milestone is reliable in-app playback from a saved server address. Catalog polish follows that proof. Top Shelf, shared profiles, synced history, and optional server remuxing can follow later.
