# Apple TV UI refinement

8 October 2026

The design keeps native top navigation and horizontal shelves. Settings uses a gear with an accessible name and no visible tab text.

## Research and decisions

- Apple recommends clear focus feedback and room for focused controls to expand. Cards now have an inset focus border, a subtle background, and more shelf spacing. Reduce Motion disables card scaling. [Apple focus guidance](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
- Apple describes television as an experience driven by a remote and viewed from a distance. Larger artwork and readable grouped text support that use. [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
- Infuse's refreshed title details emphasize artwork and the primary action. Home now has a 620-point hero, and Details uses 660 points. Backdrops fit within the image area, aligned right, instead of being cropped across a shallow full-width banner. The gradient keeps text readable. [Infuse 8](https://firecore.com/blog/infuse-8-now-available)
- Netflix's published TV redesign places navigation at the top and shows useful title information while browsing. Torrent Tube retains those existing patterns. [Netflix TV redesign](https://www.netflix.com/tudum/articles/netflix-new-tv-layout)

These are design choices informed by the references, not prescribed Apple dimensions. Poster cards use a 2:3 aspect ratio instead of a fixed 280-point height. The first shelf remains visible below the taller hero to signal more content.

Settings separates the connected server and its action from viewing-position information and player licenses. Playback and server behavior remain unchanged.

## Validation

Simulator build passed. Four remote-driven UI checks passed: Settings and Change server, poster focus restoration after Details, live-server Home and Details, and TV Shows/Cartoons navigation. Inspected rendered Home, Details, Settings, and Cartoons screenshots under `appletv/build/evidence/ui-refinement/`. The existing UIKit `_UIReplicantView` transition warning still appears; the tested navigation flows pass. Physical Apple TV verification remains open.

## Follow-up: cards and selection panels

Removed the padded border around each whole movie card. The focus outline follows only the poster; the title stays below it with consistent spacing. Version selection uses a 1200-point panel with left-aligned, wrapping release names and separate metadata. Trailers open in a full-screen browser. Audio and subtitle overlays size to their row count, preserve playback, and focus the selected track. Back closes the overlay before the player.

Verified poster focus restoration and the live-server version picker. The trailer UI test passes with audio dismissal, subtitle Off focus and selection, and return navigation. Screenshots are in `appletv/build/evidence/ui-polish/`. Physical-device review remains open.
