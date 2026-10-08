# Apple TV interface research and redesign brief

8 October 2026

**Recommendation:** use Infuse as the functional reference, Apple TV for artwork and navigation, and Netflix for information while browsing. Torrent Tube should open with films and a clear next action. The current screen gives most of its first impression to application controls.

This is comparative design research and a review of the supplied Home screenshot. Competitor evidence comes from official published screenshots and documentation, inspected during this research. These are reference designs, not a claim that every installed version looks identical. Competitor apps were not operated on a physical Apple TV.

## 1. Current Home screen — needs a structural redesign

![The supplied Torrent Tube Home screen](</Users/artsvit/Develop/Torrent Tube/appletv/design-research/01-current-home.png>)

The screenshot has useful foundations: real posters, readable titles, and familiar navigation. Its hierarchy makes choosing something to watch harder:

- The first posters start around pixel 525 of a 1080-pixel screen. The heading, warning, filters, and gaps occupy nearly half the view.
- No title has a larger artwork treatment, summary, or clear Play/Resume action on Home.
- Every card has the same weight. The repeated gray panels and large rating rows compete with the artwork.
- The feed selector resembles a settings control. Its last item is cut off, while the rows of films have no visible category headings.
- The oversized “Discover” heading repeats the already selected navigation destination.
- The persistent server warning occupies prime viewing space. Its information is useful, but it should be a compact status affordance linked to Settings. A playback attempt still needs a clear explanation when the server is incompatible.

Accessibility risks visible here: muted secondary text over a variable background may be hard to read, truncated titles lose context, and the screenshot does not show which poster has focus. Remote navigation, VoiceOver, contrast ratios, and motion need runtime checks before making accessibility claims.

## 2. Infuse — strong functional reference

![Official Infuse refreshed details reference](</Users/artsvit/Develop/Torrent Tube/appletv/design-research/02-infuse-reference.png>)

Firecore’s published details design gives artwork most of the screen. Title, brief metadata, description, and the main playback action sit together. Its documentation also separates personal-media sources, favorites, and viewing lists. This matches our server-based media use case. [Infuse 8 design reference](https://firecore.com/blog/infuse-8-now-available), [Infuse server connections](https://support.firecore.com/hc/en-us/articles/215090977-Streaming-From-a-Mac-PC-or-NAS), [Infuse settings](https://support.firecore.com/hc/en-us/articles/360015608854-Settings-Overview).

Borrow the clean title page, obvious Resume/Play priority, and easy access to audio and subtitles. Keep server setup and file management in dedicated views. Do not copy format badges until we can verify the selected file’s actual properties.

## 3. Netflix — strong browsing reference

![Official Netflix TV redesign reference](</Users/artsvit/Develop/Torrent Tube/appletv/design-research/03-netflix-reference.png>)

Netflix’s published 2025 TV redesign uses top navigation, an emphasized selected tile, and title information visible while browsing. Its personal hub brings viewing progress and saved items together. This differs from the older Netflix sidebar design often used as a reference. [Netflix TV redesign](https://www.netflix.com/tudum/articles/netflix-new-tv-layout), [Netflix navigation guide](https://www.netflix.com/tudum/articles/netflix-new-homepage-layout-user-guide).

Borrow horizontal shelves and a clear visual response to focus. Show the selected title’s summary and useful metadata without requiring a details visit. Our rows must use real server feeds; personalized recommendations or “Top 10” labels require data we currently do not have.

## 4. Apple TV — strong platform reference

![Official Apple TV artwork and sidebar reference](</Users/artsvit/Develop/Torrent Tube/appletv/design-research/04-apple-tv-reference.png>)

Apple’s reference pairs large featured artwork with a sidebar and content rows. Its guide describes featured items, Continue Watching, category rows, and title pages with episodes and related information. Its tvOS guidance emphasizes visible focus and readability across the room. [Apple TV navigation](https://support.apple.com/guide/tv/navigate-the-apple-tv-app-atvb59b423ba/27/tvos/27), [Apple TV browsing](https://support.apple.com/guide/tv/find-things-to-watch-atvb7d7bec9f/27/tvos/27), [tvOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos).

Borrow the artwork hierarchy, clear separation of browsing and personal library, and predictable focus. A sidebar is one valid navigation pattern; our existing native top navigation can also work. The main redesign should start with content layout.

## Proposed Torrent Tube experience

These are design recommendations inferred from the references, not Apple requirements.

**Home:** a wide backdrop with the selected film’s title, short metadata, two-line summary, and Play/Resume plus Details. Keep the first content shelf visible below it. Use compact navigation for Home, Movies, TV Shows, Cartoons, Search, and Settings. This includes the user’s later correction: Cartoons follows TV Shows and replaces Library. Preserve Torrent Tube’s blue accent for focused items and important actions.

**Shelves:** Continue Watching first when it has content, then New, Popular, Movies, TV Shows, Cartoons, and Ukrainian. Use landscape thumbnails and progress bars for Continue Watching; use posters for catalog shelves. Category pages can retain a dense grid and filters. Keep Home available when search is disabled.

**Cards:** artwork, a short title, and a restrained focus treatment. Move the large ratings into the selected title’s information area. Reveal the full title there when a card label is truncated. Reserve space so focus enlargement cannot collide with neighboring cards.

**Details:** full backdrop, title, readable summary, and a strong Play/Resume action. Put episode thumbnails and season selection below. Keep release selection in a clearly named “Choose version” view with file size, seeders, and available source information. Keep the Apple TV app focused on streaming, with no Download action or queue controls. This follows the user’s explicit correction on 8 October.

**Player:** video fills the screen. Show a light control overlay on interaction, with time, seeking, audio, and subtitles. Hide it during playback. Buffering should explain progress only when useful. Preserve remote play/pause, predictable Back, and saved positions.

## Implementation order and data needs

1. Create visual concepts for Home, Details, and Player, grounded in these screenshots. Select a consistent direction before changing those screens.
2. Build the Home backdrop and horizontal shelves. Current `/api/details` already returns backdrop, year, runtime, genres, and season information. Discover enrichment lacks backdrop and compact title facts, so fetch/cache details for the active title or extend the metadata response.
3. Refine details, episode presentation, and release selection. Torrent files are available, but mapping episode filenames to TMDB still images needs new logic and safe filename fallbacks.
4. Refine the playback overlay without changing the working streaming/session behavior.
5. Verify focus restoration, long Ukrainian titles, missing artwork, disabled search, incompatible servers, and loading failures on the simulator and a physical Apple TV.

Use higher-resolution artwork for large surfaces. Load shelves progressively and keep network requests from blocking focus movement. Artwork changes should settle after focus, and reduced-motion settings must suppress decorative transitions.

This report records the research pass. The subsequent streaming redesign implements the chosen direction; see the Apple TV README for current behavior and verification.
