import SwiftUI

/// Menu on a title page: back to the top level of the tab it's in (or out of
/// a Top Shelf title) - not one step, so a chain of "More Like This" titles
/// doesn't take a press per title.
private struct BackToTopKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var backToTop: () -> Void {
        get { self[BackToTopKey.self] }
        set { self[BackToTopKey.self] = newValue }
    }
}

enum MainTab: Hashable { case home, movies, tv, cartoons, library, search, settings }

private struct BackScrollAction: Equatable {
    let id: UUID
    let scroll: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

private struct BackScrollPreference: PreferenceKey {
    static let defaultValue: [BackScrollAction] = []
    static func reduce(value: inout [BackScrollAction], nextValue: () -> [BackScrollAction]) {
        value += nextValue()
    }
}

private struct BackDismissPreference: PreferenceKey {
    static let defaultValue: [BackScrollAction] = []
    static func reduce(value: inout [BackScrollAction], nextValue: () -> [BackScrollAction]) { value += nextValue() }
}

struct MainView: View {
    let store: AppStore
    let api: TorrentTubeAPI
    let config: ServerConfig
    @State private var catalog = CatalogStore()
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ResumeHistory.self) private var history
    @State private var shelfTitle: MediaItem?
    @State private var tab: MainTab = .home
    // Each tab's own stack of title pages. Leaving a tab resets it, so
    // coming back shows its top level, not the movie last opened there.
    @State private var paths: [MainTab: NavigationPath] = [:]
    @State private var settingsReset = 0
    @State private var backScrollActions: [BackScrollAction] = []
    @State private var needsHomeReturn = false
    @State private var backDismissActions: [BackScrollAction] = []
    @State private var librarySection = ""
    @State private var libraryScrollRequest = UUID()
    @State private var libraryReturnID = UUID()
    @FocusState private var libraryChip: String?
    @FocusState private var navigationFocus: MainTab?
    @Environment(\.scenePhase) private var scenePhase
    private func path(_ tab: MainTab) -> Binding<NavigationPath> {
        Binding(get: { paths[tab] ?? NavigationPath() }, set: { setPath($0, for: tab) })
    }
    private func setPath(_ path: NavigationPath, for tab: MainTab) {
        if tab == .library, !(paths[tab]?.isEmpty ?? true), path.isEmpty {
            // A fresh root prevents tvOS from restoring its cached poster focus.
            // The selected category stays in MainView.
            libraryReturnID = UUID()
        }
        paths[tab] = path
    }
    /// A tab's stack, with title pages pushed as values so it can be reset.
    private func stack<Root: View>(_ tab: MainTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path(tab)) {
            root().navigationDestination(for: MediaItem.self) { item in TitleView(item: item, api: api, config: config) }
                .navigationDestination(for: PersonRoute.self) { PersonView(route: $0, api: api, config: config) }
        }
        .environment(\.backToTop) { setPath(NavigationPath(), for: tab) }
    }
    var body: some View {
        Group {
            switch tab {
            case .home: stack(.home) { HomeView(api: api, config: config) }
            case .movies: stack(.movies) { CategoryView(feed: "movies", title: "Movies", api: api, config: config) }
            case .tv: stack(.tv) { CategoryView(feed: "tv", title: "TV Shows", api: api, config: config) }
            case .cartoons: stack(.cartoons) { CategoryView(feed: "cartoons", title: "Cartoons", api: api, config: config) }
            case .library: stack(.library) { LibraryView(api: api, config: config, section: $librarySection, chipFocus: $libraryChip, scrollRequest: libraryScrollRequest).id(libraryReturnID) }
            case .search: stack(.search) { SearchView(api: api, config: config) }
            case .settings: NavigationStack { SettingsView(store: store, api: api, config: config).padding(.top, 118) }.id(settingsReset)
            }
        }
        // NavigationStack does not pass an outer safe-area inset to every root.
        // Reserve actual layout space so fixed screens cannot sit behind the bar.
        .overlay(alignment: .top) { navigationBar }
        .onPreferenceChange(BackScrollPreference.self) { backScrollActions = $0 }
        .onPreferenceChange(BackDismissPreference.self) { backDismissActions = $0 }
        .onExitCommand(perform: backCommand)
        .onChange(of: tab) { old, _ in
            if old == .settings { settingsReset += 1 } else { paths[old] = NavigationPath() }
        }
        .environment(catalog)
        .background(AppBackground())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await catalog.loadFeed("new", api: api, config: config, refresh: true) }
                favorites.sync(); history.sync()  // changes on another device
            }
        }
        .task(id: api.baseURL) {
            favorites.connect(api, config: config)
            history.connect(api, config: config)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if scenePhase == .active { history.sync() }
            }
        }
        .onChange(of: store.shelfTitleID, initial: true) { _, id in
            guard let id, let snapshot = TopShelfStore.snapshot, snapshot.server == api.baseURL.absoluteString,
                  let title = snapshot.titles.first(where: { $0.id == id }) else { return }
            var item = MediaItem(title: title.rawTitle, magnet: title.magnet, downloadLink: title.downloadLink,
                                 sizeLabel: nil, seeders: nil, releases: nil)
            item.cleanTitle = title.title; item.poster = title.poster; item.tmdbId = title.tmdbID; item.mediaType = title.mediaType
            shelfTitle = item
            store.shelfTitleID = nil
        }
        .fullScreenCover(item: $shelfTitle) { item in
            NavigationStack {
                TitleView(item: item, api: api, config: config)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button(L("Back")) { shelfTitle = nil } } }
                    .navigationDestination(for: MediaItem.self) { item in TitleView(item: item, api: api, config: config) }
                    .navigationDestination(for: PersonRoute.self) { PersonView(route: $0, api: api, config: config) }
            }
            .environment(catalog)
            .environment(\.backToTop) { shelfTitle = nil }
            .onExitCommand { shelfTitle = nil }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 6) {
            navigationButton(.home, title: "Home", icon: nil)
            if config.searchEnabled {
                navigationButton(.movies, title: "Movies", icon: nil)
                navigationButton(.tv, title: "TV Shows", icon: nil)
                navigationButton(.cartoons, title: "Cartoons", icon: nil)
            }
            navigationButton(.library, title: "Library", icon: nil)
            navigationButton(.search, title: "Search", icon: "magnifyingglass", iconOnly: true)
            navigationButton(.settings, title: "Settings", icon: "gearshape", iconOnly: true)
        }
        .padding(6)
        .modifier(TVNavigationGlass())
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .focusSection()
        .defaultFocus($navigationFocus, tab)
        // Up from the page lands on the nearest item (often Home); coming
        // into the bar should land on the open tab instead.
        .onChange(of: navigationFocus) { old, new in
            if old == nil, let new, new != tab { navigationFocus = tab }
        }
    }

    private func navigationButton(_ destination: MainTab, title: String, icon: String?, iconOnly: Bool = false) -> some View {
        Button { tab = destination } label: {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).environment(\.symbolVariants, .none) }
                if !iconOnly { Text(L(title)) }
            }
            .lineLimit(1)
        }
        .buttonStyle(TVNavigationButtonStyle(selected: tab == destination, iconOnly: iconOnly))
        .accessibilityIdentifier("main-tab-\(destination)")
        .focused($navigationFocus, equals: destination)
        .accessibilityLabel(L(title))
        .accessibilityAddTraits(tab == destination ? .isSelected : [])
    }

    private var backCommand: (() -> Void)? {
        if let action = backDismissActions.last { return action.scroll }
        if tab == .library, paths[tab]?.isEmpty ?? true {
            if libraryChip == nil {
                return {
                    let selected = librarySection.isEmpty ? LibrarySections.defaultSection(catalog.library) : librarySection
                    libraryChip = selected
                    libraryScrollRequest = UUID()
                }
            }
            return { needsHomeReturn = false; tab = .home; navigationFocus = .home }
        }

        if let action = backScrollActions.last {
            return {
                needsHomeReturn = true
                backScrollActions.removeAll()
                navigationFocus = tab
                withAnimation(.easeOut(duration: 0.3)) { action.scroll() }
            }
        }
        if !(paths[tab]?.isEmpty ?? true) {
            return {
                needsHomeReturn = false
                var path = paths[tab] ?? NavigationPath()
                path.removeLast()
                setPath(path, for: tab)
            }
        }
        guard needsHomeReturn || tab != .home else { return nil }
        return {
            needsHomeReturn = false
            paths[tab] = NavigationPath()
            paths[.home] = NavigationPath()
            tab = .home
            navigationFocus = .home
        }
    }
}

private struct TVNavigationGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(tvOS 26.0, *) {
            content.glassEffect(.clear.tint(.black.opacity(0.3)), in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
    }
}

private struct TVNavigationButtonStyle: ButtonStyle {
    let selected: Bool
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        NavigationLabel(content: configuration.label, selected: selected, iconOnly: iconOnly)
    }
    private struct NavigationLabel<Content: View>: View {
        let content: Content
        let selected: Bool
        let iconOnly: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            content
                .font(.system(size: 26, weight: .semibold))
                .padding(.horizontal, iconOnly ? 0 : 20)
                .frame(width: iconOnly ? 66 : nil, height: 62)
                .foregroundStyle(focused ? .black : .white)
                .background(focused ? Color.white : (selected ? Color.white.opacity(0.22) : Color.clear), in: Capsule())
        }
    }
}

/// One left edge for the whole Home: hero text, shelf titles and cards.
enum TVLayout {
    static let edge: CGFloat = 90
    static let heroHeight: CGFloat = 920
}

struct UpdateServerNotice: View {
    var body: some View {
        Label(L("Update your server to enable streaming on this Apple TV."), systemImage: "exclamationmark.circle")
            .font(.system(size: 24)).foregroundStyle(.orange)
    }
}

struct HomeView: View {
    @AppStorage("showContinueWatching") private var showContinueWatching = true
    @AppStorage("previewFocusedTitle") private var previewFocusedTitle = true
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(ResumeHistory.self) private var history
    @Environment(\.scenePhase) private var scenePhase
    private enum HeroAction: Hashable { case play, details, trailer, mute, pages }
    @FocusState private var heroAction: HeroAction?
    @State private var featuredIndex = 0
    @State private var heroVisible = true
    @State private var preview = HomeTrailerPreview()
    @State private var showServerNotice = false
    @State private var highlighted: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var trailer: Trailer?
    @State private var findingTrailer = false
    @State private var trailerError: String?
    private func playTrailer(_ item: MediaItem) {
        findingTrailer = true; trailerError = nil
        Task {
            defer { findingTrailer = false }
            do {
                let details = catalog.details[item.title]
                if let found = try await TrailerChoice.find(title: details?.title ?? item.displayTitle, year: details?.year, known: details?.trailers ?? [], api: api) {
                    trailer = found
                } else { trailerError = L("No trailer was found for this title.") }
            } catch { trailerError = error.localizedDescription }
        }
    }
    private let shelves = [("new", "New to Explore"), ("popular", "Popular Now"), ("movies", "Movies"), ("tv", "TV Shows"), ("cartoons", "Cartoons"), ("ukrainian", "Ukrainian")]
    private var recent: [ResumeEntry] { history.entries.filter { $0.server == api.baseURL.absoluteString } }
    private var featured: [MediaItem] {
        let selected = catalog.homeFeatured
        return selected.isEmpty ? Array(catalog.library.prefix(HomeFeaturedSelection.limit).map(libraryItem)) : selected
    }
    private var active: MediaItem? {
        (previewFocusedTitle ? highlighted : nil) ?? (featured.isEmpty ? nil : featured[min(featuredIndex, featured.count - 1)])
    }
    private var previewAllowed: Bool { heroVisible && heroAction != nil && scenePhase == .active && playback == nil }
    private struct RotationCycle: Equatable {
        let index: Int
        let titles: [String]
    }
    private var rotationCycle: RotationCycle? {
        guard featured.count > 1, heroVisible, scenePhase == .active, playback == nil,
              !showServerNotice, highlighted == nil, !preview.loading, preview.controller == nil else { return nil }
        return RotationCycle(index: featuredIndex, titles: featured.map(\.id))
    }
    var body: some View {
        ScrollView {
            // Keep shelf frames and focus sections alive when moving vertically.
            // Each horizontal shelf still creates its posters lazily.
            VStack(alignment: .leading, spacing: 54) {
                if let active {
                    CinemaHero(item: catalog.resolved(active), details: catalog.details[active.title], height: 1080, bottomInset: 245, overviewLines: nil, preview: preview.controller, nextArtwork: nextHeroArtwork) {
                        // Actions stay on the left; page indicators align with the right screen margin.
                        HStack(spacing: 28) {
                            Button {
                                preview.stop()
                                if config.supportsPlayback { playback = playRequest(active) } else { showServerNotice = true }
                            } label: { Label(L("Play"), systemImage: "play.fill") }
                                .buttonStyle(WatchButtonStyle())
                                .accessibilityIdentifier("hero-play").focused($heroAction, equals: .play)
                            NavigationLink(value: active) { Label(L("Details"), systemImage: "info.circle") }
                                .buttonStyle(.bordered).tint(.white).focused($heroAction, equals: .details)
                            Button { playTrailer(active) } label: {
                                Label(L(findingTrailer ? "Finding trailer…" : "Trailer"), systemImage: "play.rectangle")
                            }.disabled(findingTrailer)
                                .buttonStyle(.bordered).tint(.white).accessibilityIdentifier("hero-trailer").focused($heroAction, equals: .trailer)
                            Group {
                                if let trailerError { Text(trailerError).lineLimit(2) }
                            }
                            .font(.system(size: 22)).foregroundStyle(.secondary).frame(maxWidth: 340, alignment: .leading)
                            Spacer(minLength: 32)
                            if featured.count > 1 {
                                HeroPageDots(count: featured.count, current: highlighted == nil ? featuredIndex : nil) { changeFeatured(1) }
                                    .focused($heroAction, equals: .pages)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, TVLayout.edge)
                    }
                    // The first row rises into the banner's fade. The banner gives up that
                    // height itself; poster creation stays lazy inside each shelf.
                    .padding(.bottom, -210)
                } else if catalog.loading.contains("new") || catalog.libraryLoading {
                    LoadingState(text: L("Finding something to watch…"), minHeight: 600)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L("Your next movie night")).font(.system(size: 64, weight: .bold))
                        Text(config.searchEnabled ? L("Explore your server’s catalog below.") : L("Ready-to-watch titles from your server appear here."))
                            .foregroundStyle(.secondary)
                    }.padding(.horizontal, TVLayout.edge).padding(.top, 220).frame(maxWidth: .infinity, minHeight: 560, alignment: .leading)
                }
                if showContinueWatching && !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        ShelfHeader(text: L("Continue Watching"))
                        ScrollView(.horizontal) {
                            HStack(spacing: 36) {
                                ForEach(recent) { entry in
                                    let resumeItem = MediaItem(title: entry.title, magnet: entry.source.magnet, downloadLink: entry.source.downloadLink,
                                                               sizeLabel: nil, seeders: nil, releases: nil, sourceOverride: entry.source)
                                    Button { playback = PlaybackRequest(source: entry.source, title: entry.title, artwork: entry.artwork) } label: {
                                        VStack(alignment: .leading, spacing: 14) {
                                            // Progress sits on the artwork, like the TV app's Up Next.
                                            ArtworkView(url: entry.artwork, seed: entry.title).frame(width: 400, height: 225)
                                                .overlay(alignment: .bottom) {
                                                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 70)
                                                }
                                                .overlay(alignment: .bottomLeading) {
                                                    ProgressView(value: entry.seconds, total: max(1, entry.duration)).tint(.white)
                                                        .padding(.horizontal, 18).padding(.bottom, 16)
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                                .overlay(alignment: .topTrailing) {
                                                    FavoritePosterBadge(item: catalog.resolved(resumeItem), server: api.baseURL)
                                                }
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                                                Text(L("Resume at %@", entry.displayPosition)).font(.system(size: 20)).foregroundStyle(.white.opacity(0.55))
                                            }.padding(.horizontal, 4)
                                        }.frame(width: 400)
                                    }.buttonStyle(CinemaCardStyle())
                                }
                            }.padding(.horizontal, TVLayout.edge).padding(.vertical, 18)
                        }.scrollIndicators(.hidden).focusSection()
                    }
                    
                }
                if config.searchEnabled {
                    ForEach(Array(shelves.enumerated()), id: \.element.0) { index, shelf in
                        let (feed, label) = shelf
                        if let items = catalog.rows[feed], !items.isEmpty {
                            MediaShelf(title: L(label), items: Array(items.prefix(24)), api: api, config: config) { if previewFocusedTitle { highlighted = $0 } }
                                // The first shelf rises into the hero's fade, unless Continue Watching already did.
                        } else if let error = catalog.errors[feed] {
                            ErrorPanel(message: "\(L(label)): \(error)") { Task { await catalog.loadFeed(feed, api: api, config: config, refresh: true) } }.padding(.horizontal, TVLayout.edge)
                        }
                    }
                }
                if !catalog.library.isEmpty {
                    MediaShelf(title: L("New on your server"), items: catalog.library.prefix(24).map(libraryItem), api: api, config: config) { if previewFocusedTitle { highlighted = $0 } }
                }
                if !config.searchEnabled && catalog.library.isEmpty && recent.isEmpty {
                    if let error = catalog.libraryError {
                        ErrorPanel(message: error) { Task { await catalog.loadLibrary(api: api) } }.padding(.horizontal, TVLayout.edge)
                    } else {
                        Text(L("Connect a media source on your server to start watching.")).foregroundStyle(.secondary).padding(.horizontal, TVLayout.edge)
                    }
                }
            }.padding(.bottom, 80)
        }
        // Edge to edge: the hero's image runs under the tab bar and to the
        // screen's sides; everything else keeps TVLayout.edge itself.
        .scrollClipDisabled()
        .tvScrollEdge()  // before ignoresSafeArea, so the fade spans the whole screen
        .ignoresSafeArea(edges: [.top, .horizontal])
        .background(AppBackground())
        .defaultFocus($heroAction, .play, priority: .userInitiated)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < 260
        } action: { _, visible in heroVisible = visible }
        .onChange(of: active?.id) { _, _ in preview.stop() }
        .onChange(of: previewAllowed) { _, allowed in if !allowed { preview.stop() } }
        .onChange(of: heroAction) { _, action in if action != nil { highlighted = nil } }
        .onDisappear { preview.stop() }
        .fullScreenCover(item: $playback) { request in PlaybackLauncher(request: request, api: api) }
        .fullScreenCover(item: $trailer) { trailer in TrailerPlayer(trailer: trailer, api: api) }
        .alert(L("Streaming unavailable"), isPresented: $showServerNotice) { Button(L("OK"), role: .cancel) {} } message: { Text(L("Update Torrent Tube on your server to stream on this Apple TV.")) }
        .task {
            await catalog.loadLibrary(api: api)
            Task { await catalog.syncLibrary(api: api, config: config) }  // new library titles only
            await catalog.loadFeed("new", api: api, config: config)
            await withTaskGroup(of: Void.self) { group in
                for (feed, _) in shelves.dropFirst() {
                    group.addTask { await catalog.loadFeed(feed, api: api, config: config) }
                }
            }
        }
        .task(id: active?.id) {
            guard let active else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await catalog.loadDetails(active, api: api, config: config)
        }
        .task(id: rotationCycle) {
            guard rotationCycle != nil else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            changeFeatured(1)
        }
    }
    private var nextHeroArtwork: String? {
        guard featured.count > 1, highlighted == nil else { return nil }
        let next = catalog.resolved(featured[(min(featuredIndex, featured.count - 1) + 1) % featured.count])
        return catalog.details[next.title]?.backdrop ?? next.poster
    }

    private func changeFeatured(_ step: Int) {
        guard !featured.isEmpty else { return }
        preview.stop(); highlighted = nil
        featuredIndex = (min(featuredIndex, featured.count - 1) + step + featured.count) % featured.count
    }
    private func playRequest(_ item: MediaItem) -> PlaybackRequest {
        let resolved = catalog.resolved(item)
        return PlaybackRequest(source: item.source, title: resolved.displayTitle, artwork: catalog.details[item.title]?.backdrop ?? resolved.poster, tmdbID: resolved.tmdbId,
                               seasonSources: item.librarySources)
    }
}


/// Home's featured titles as dots beside the buttons. Focus them and press
/// (or swipe right) for the next title; the wide dot is the current one.
struct HeroPageDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let current: Int?
    let next: () -> Void
    var body: some View {
        Button(action: next) {
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule().fill(.white.opacity(index == current ? 1 : 0.35))
                        .frame(width: index == current ? 26 : 9, height: 9)
                }
            }
            .padding(.horizontal, 22).frame(height: 66)
        }
        .buttonStyle(DotsStyle())
        .onMoveCommand { if $0 == .right { next() } }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current)
        .accessibilityLabel(L("Featured title %ld of %ld", (current ?? 0) + 1, count))
        .accessibilityHint(L("Next featured title"))
        .accessibilityIdentifier("hero-next")
    }
    /// No lift or glow: a faint pill shows focus, so the dots never jump.
    private struct DotsStyle: ButtonStyle {
        @Environment(\.isFocused) private var focused
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(.white.opacity(focused ? 0.18 : 0), in: Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// The big image at the top: the backdrop fills the whole width and runs
/// under the tab bar, with dark scrims for the text on the left, the tab
/// bar on top and a long fade into the page at the bottom.
struct CinemaHero<Actions: View>: View {
    let item: MediaItem
    let details: Details?
    let height: CGFloat
    /// Space under the buttons - Home leaves room for its first shelf, which
    /// rises into the fade.
    var bottomInset: CGFloat = 70
    /// Description visibility in the hero.
    var showsOverview = true
    /// Use nil to show the full description and let the hero grow to fit it.
    var overviewLines: Int? = 3
    /// Title pages show the credits at the right.
    var showsCredits = false
    var preview: EmbeddedPlayer? = nil
    var nextArtwork: String? = nil
    @ViewBuilder let actions: () -> Actions
    private var kind: String? {
        let type = details?.mediaType ?? item.mediaType
        if details?.kind == "Cartoon" { return type == "tv" ? L("Animated Series") : L("Cartoon") }
        switch type {
        case "tv": return L("TV Show")
        case "movie": return L("Movie")
        default: return nil
        }
    }
    private var facts: [String] {
        var list: [String] = []
        if let year = details?.year, !year.isEmpty { list.append(year) }
        if let runtime = details?.runtime, runtime > 0 { list.append(runtime >= 60 ? L("%ld h %ld min", runtime / 60, runtime % 60) : L("%ld min", runtime)) }
        return list  // genres are in the line under the title
    }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                HeroBackdrop(url: (details?.backdrop ?? item.poster).flatMap { URL(string: higherResolution($0, backdrop: true)) },
                             nextURL: nextArtwork.flatMap { URL(string: higherResolution($0, backdrop: true)) },
                             placeholder: item.displayTitle)
                if let preview {
                    VideoSurface(controller: preview)
                        .opacity(preview.playing && !preview.buffering ? 1 : 0)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.55), location: 0.35),
                                       .init(color: .clear, location: 0.72)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28))
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.7), location: 0.8),
                                       .init(color: .black, location: 1.0)], startPoint: .top, endPoint: .bottom)
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.45),
                    .init(color: .white.opacity(0.85), location: 0.65),
                    .init(color: .white.opacity(0.35), location: 0.86),
                    .init(color: .clear, location: 1.0)
                ], startPoint: .top, endPoint: .bottom)
            )
            // In the way of the Apple TV app: a modest title, kind and genres,
            // the description, year and length with the rating, the buttons,
            // and the credits on the right - the same order as on iPhone, iPad and Mac.
            HStack(alignment: .bottom, spacing: 60) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(details?.title ?? item.displayTitle).font(.system(size: 64, weight: .bold)).lineLimit(2).tightTitleLines(size: 64)
                        .accessibilityIdentifier("hero-title")
                        .minimumScaleFactor(0.7).shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                        .frame(maxWidth: 1000, alignment: .leading)
                    HStack(spacing: 12) {
                        Text(BannerText.subtitle(kind: kind, details: details)).lineLimit(1)
                        if let certification = details?.certification, !certification.isEmpty {
                            Text(certification).font(.system(size: 19, weight: .bold))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.6), lineWidth: 2))
                        }
                    }
                    .font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.85)).padding(.top, 14)
                    if showsOverview, (details?.tagline ?? "").isEmpty == false || (details?.overview ?? item.overview ?? "").isEmpty == false {
                        VStack(alignment: .leading, spacing: 6) {
                            // The tagline heads the description.
                            if let tagline = details?.tagline, !tagline.isEmpty {
                                Text(tagline).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(overviewLines == nil ? nil : 2)
                            }
                            if let overview = details?.overview ?? item.overview, !overview.isEmpty {
                                Text(overview).font(.system(size: 24)).foregroundStyle(.white.opacity(0.78)).lineSpacing(3)
                                    .lineLimit(overviewLines)
                                    .fixedSize(horizontal: false, vertical: overviewLines == nil)
                            }
                        }
                        .frame(maxWidth: 820, alignment: .leading).padding(.top, 16)
                    }
                    HStack(spacing: 14) {
                        if !facts.isEmpty { Text(facts.joined(separator: " · ")) }
                        if let rating = item.rating, rating > 0 {
                            // A golden star, like a rating; the number stays white.
                            Label { Text(String(format: "%.1f", rating)).accessibilityIdentifier("hero-rating") } icon: {
                                Image(systemName: "star.fill").foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.2))
                            }.labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(.white.opacity(0.7)).padding(.top, 14)
                    actions().padding(.top, 28).focusSection()
                }
                if showsCredits {
                    Spacer(minLength: 0)
                    let credits = BannerText.credits(details: details)
                    if !credits.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(credits, id: \.label) { line in
                                (Text(line.label + " ").foregroundStyle(.white.opacity(0.55)) + Text(line.names).foregroundStyle(.white.opacity(0.9)))
                                    .lineLimit(2)
                            }
                        }
                        .font(.system(size: 22)).frame(maxWidth: 520, alignment: .leading)
                    }
                }
            }
            .padding(.trailing, showsCredits ? TVLayout.edge : 0)
            .padding(.leading, TVLayout.edge).padding(.bottom, bottomInset)
            .padding(.top, overviewLines == nil ? 180 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: overviewLines == nil ? nil : height)
        .frame(minHeight: overviewLines == nil ? height : nil)
        .clipped()
        .focusSection()
    }
}

/// Watch stays white at rest and uses the player accent when focused.
struct WatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionLabel(content: configuration.label, pressed: configuration.isPressed)
    }
    private struct ActionLabel<Content: View>: View {
        let content: Content
        let pressed: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            content
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(focused ? Color.white : Color.black)
                .padding(.horizontal, 30).frame(height: 68)
                .background(focused ? Color.torrentAccent : Color.white, in: Capsule())
                .opacity(enabled ? (pressed ? 0.8 : 1) : 0.45)
        }
    }
}

struct ArtworkView: View {
    let url: String?
    var background = false
    /// Fill the frame edge to edge (the hero) instead of fitting a backdrop
    /// to the right side.
    var fill = false
    /// The title: it picks the branded placeholder's color.
    var seed = ""
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !background {
                    Color(white: 0.07)
                }
                if let url, let address = URL(string: higherResolution(url, backdrop: background)) {
                    if !background {
                        PosterArtwork(url: address, seed: seed)
                    } else {
                        AsyncImage(url: address, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                            if let image = phase.image {  // fades in instead of popping in
                                image.resizable().aspectRatio(contentMode: background && !fill ? .fit : .fill).transition(.opacity)
                            } else { Color.clear }
                        }
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: background && !fill ? .trailing : .center)
                            .clipped()
                    }
                } else if !background {
                    BrandPlaceholder(seed: seed)
                }
            }
        }.clipped()
    }
}

struct CinemaCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CinemaCardLabel(content: configuration.label, pressed: configuration.isPressed)
    }
    struct CinemaCardLabel<Content: View>: View {
        let content: Content
        let pressed: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reducedMotion
        var body: some View {
            content
                .scaleEffect(reducedMotion ? 1 : (focused ? (pressed ? 1.03 : 1.08) : 1))
                .shadow(color: .black.opacity(focused ? 0.7 : 0), radius: focused ? 28 : 0, y: focused ? 18 : 0)
                .animation(reducedMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: focused)
        }
    }
}

struct MediaShelf: View {
    let title: String
    let items: [MediaItem]
    let api: TorrentTubeAPI
    let config: ServerConfig
    var onFocus: (MediaItem) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShelfHeader(text: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 36) {
                    ForEach(items) { item in FilmCard(item: item, api: api, config: config, onFocus: onFocus).frame(width: 236) }
                }.padding(.horizontal, TVLayout.edge).padding(.vertical, 24)
            }.scrollIndicators(.hidden).scrollClipDisabled().focusSection()
        }
    }
}

/// A round photo with name and role - Cast & Crew. Focusable so the
/// row can be browsed with the remote; selecting it does nothing.
extension View {
    /// Content fades out over its top `height` points instead of ending in a hard edge under the bar.
    func tvTopFade(_ height: CGFloat) -> some View {
        // The mask ignores the safe area too, or it would cut an edge-to-edge image back to the safe area.
        mask(VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: height)
            Color.black
        }.ignoresSafeArea())
    }
    /// For screens whose banner runs under the bar: the top edge fades only once the page has scrolled,
    /// so the banner still reaches the top edge at rest.
    func tvScrollEdge(_ height: CGFloat = 170) -> some View { modifier(TVScrollEdge(height: height)) }
    func tvBackScroll() -> some View { modifier(TVBackScroll()) }
}

private struct TVBackScroll: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)
    @State private var scrolled = false
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear { id = UUID() }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { _, value in scrolled = value }
            .preference(key: BackScrollPreference.self,
                        value: scrolled ? [BackScrollAction(id: id, scroll: { position.scrollTo(edge: .top) })] : [])
    }
}

private struct TVScrollEdge: ViewModifier {
    let height: CGFloat
    @State private var scrolled = false
    func body(content: Content) -> some View {
        content
            .tvBackScroll()
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { _, new in scrolled = new }
            .tvTopFade(scrolled ? height : 0)
            .animation(.easeOut(duration: 0.25), value: scrolled)
    }
}

struct PersonCard: View {
    let person: Details.Person
    @FocusState private var focused: Bool
    /// A cast photo opens that person's films and shows.
    @ViewBuilder private func personLink<Content: View>(@ViewBuilder _ label: () -> Content) -> some View {
        if let route = person.route { NavigationLink(value: route, label: label) } else { Button(action: {}, label: label) }
    }
    var body: some View {
        personLink { VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(white: 0.14))
                    if let photo = person.photo, let url = URL(string: photo) {
                        AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                    } else {
                        Text(String(person.name.prefix(1))).font(.system(size: 54, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 170, height: 170).clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 3 : 1))
                VStack(spacing: 4) {
                    Text(person.name).font(.system(size: 21, weight: .semibold)).lineLimit(2)
                    if let role = person.role, !role.isEmpty {
                        Text(L(role)).font(.system(size: 18)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                    }
                }.multilineTextAlignment(.center).foregroundStyle(focused ? .white : .white.opacity(0.85))
            }.frame(width: 190) }
        .buttonStyle(CinemaCardStyle()).focused($focused)
        .accessibilityLabel([person.name, person.role.map { L($0) }].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Facts in columns - label above value - under a title's description.
struct InfoGrid: View {
    let rows: [(String, String)]
    @FocusState private var focused: Bool
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 48, alignment: .topLeading), count: 3),
                  alignment: .leading, spacing: 30) {
            ForEach(rows, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label.uppercased()).font(.system(size: 18, weight: .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.45))
                    Text(value).font(.system(size: 23)).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                }
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(focused ? 0.1 : 0.05)))
        // Focusable, so the remote can scroll down to it when it's last.
        .focusable().focused($focused)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct ShelfHeader: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 34, weight: .bold)).foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, TVLayout.edge)
    }
}

struct FilmCard: View {
    let item: MediaItem
    let api: TorrentTubeAPI
    let config: ServerConfig
    var onFocus: (MediaItem) -> Void = { _ in }
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @FocusState private var focused: Bool
    var body: some View {
        let value = catalog.resolved(item)
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 14) {
                ArtworkView(url: value.poster, seed: value.displayTitle).aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 3 : 1) }
                    // A favorite, in every grid and shelf - as on iPhone and iPad.
                    .overlay(alignment: .topTrailing) {
                        FavoritePosterBadge(item: value, server: api.baseURL)
                    }
                Text(value.displayTitle).font(.system(size: 21, weight: .semibold)).foregroundStyle(focused ? .white : .white.opacity(0.6)).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading).padding(.horizontal, 4)
            }
        }
        .buttonStyle(CinemaCardStyle()).focused($focused)
        .accessibilityLabel(value.displayTitle).accessibilityIdentifier("title-\(item.id)")
        // Hold Select on a poster: add to or remove from Favorites.
        .contextMenu {
            let saved = favorites.contains(value, server: api.baseURL)
            Button {
                Task {
                    // Its details say movie, show or cartoon - the Favorites tab it goes to.
                    if !saved { await catalog.loadDetails(item, api: api, config: config) }
                    favorites.toggle(value, details: catalog.details[item.title], server: api.baseURL)
                }
            } label: {
                Label(saved ? L("Remove from Favorites") : L("Add to Favorites"), systemImage: saved ? "heart.slash" : "heart")
            }
        }
        .onChange(of: focused) { _, isFocused in if isFocused { onFocus(item) } }
        .task(id: item.id) { await catalog.enrich([item], api: api, config: config) }
    }
}

struct CategoryView: View {
    let feed: String
    let title: String
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @State private var selected = ""
    private var activeFeed: String { selected.isEmpty ? feed : selected }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                Text(L(["docs": "Documentaries", "cartoons": "Cartoons", "ukrainian": "Ukrainian"][activeFeed] ?? title)).font(.system(size: 50, weight: .bold))
                // Movies has sub-categories; the catalog refreshes itself when the app opens.
                if feed == "movies" {
                    ChipRow(options: [("movies", "All"), ("docs", "Documentaries"), ("ukrainian", "Ukrainian")], selected: activeFeed) { selected = $0 }
                }
                if catalog.loading.contains(activeFeed) && catalog.rows[activeFeed] == nil { LoadingState(text: L("Loading titles…"), minHeight: 700) }
                if let error = catalog.errors[activeFeed] { ErrorPanel(message: error) { Task { await catalog.loadFeed(activeFeed, api: api, config: config, refresh: true) } } }
                if catalog.rows[activeFeed]?.isEmpty == true && !catalog.loading.contains(activeFeed) && catalog.errors[activeFeed] == nil {
                    ContentUnavailableView(L("Nothing here yet"), systemImage: "film", description: Text(L("Try another category or refresh your server’s catalog.")))
                        .frame(maxWidth: .infinity, minHeight: 500)
                }
                FilmGrid(items: catalog.rows[activeFeed] ?? [], api: api, config: config)
            }.padding(.horizontal, TVLayout.edge).padding(.top, 158 + ScreenLayout.top).padding(.bottom, 70)
        }
        .tvScrollEdge()
        .ignoresSafeArea(edges: .horizontal)
        .task(id: activeFeed) { await catalog.loadFeed(activeFeed, api: api, config: config) }
    }
}

/// Space between the tab bar and a screen's title - half of what it was.
enum ScreenLayout {
    static let top: CGFloat = 0
}

/// Tabs inside a screen (Movies, Favorites): one chip each, the current one filled.
struct ChipRow: View {
    let options: [(String, String)]
    let selected: String
    let select: (String) -> Void
    var externalFocus: FocusState<String?>.Binding? = nil
    @FocusState private var focusedChip: String?
    var body: some View {
        HStack(spacing: 20) {
            ForEach(options, id: \.0) { key, label in
                let current = selected == key
                Button { select(key) } label: { Text(L(label)) }
                    .buttonStyle(ChipStyle(selected: current))
                    .accessibilityAddTraits(current ? .isSelected : [])
                    .accessibilityIdentifier("library-chip-\(key)")
                    .focused(externalFocus ?? $focusedChip, equals: key)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // Up from any poster reaches the chips
        .focusSection()
    }
}

/// A chip that never moves: no focus lift, one font weight in every state.
/// Focus turns it white; the chosen one is filled with the accent.
struct ChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        Chip(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
    private struct Chip<Label: View>: View {
        let label: Label
        let selected: Bool
        let pressed: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            label
                .font(.system(size: 29, weight: .semibold))
                .padding(.horizontal, 32).frame(height: 66)
                .foregroundStyle(focused ? .black : .white)
                .background(focused ? Color.white.opacity(pressed ? 0.8 : 1) : (selected ? Color.torrentAccent : Color.white.opacity(0.12)),
                            in: Capsule())
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

struct FilmGrid: View {
    let items: [MediaItem]
    let api: TorrentTubeAPI
    let config: ServerConfig
    var onFocus: (MediaItem) -> Void = { _ in }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 36)], alignment: .leading, spacing: 36) {
            ForEach(items) { item in FilmCard(item: item, api: api, config: config, onFocus: onFocus) }
        }.padding(.vertical, 16)
        // As wide as the screen and its own section: Down from a chip or a
        // poster with nothing right below it (a short row above) still comes
        // in, to the nearest poster.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// Search with our own keyboard on the left - Ukrainian and English
/// layouts (the app's language first), digits, space and delete - and live
/// results on the right. The system keyboard can't offer Ukrainian unless
/// the Apple TV has it enabled, and it moved focus on its own. A hardware
/// keyboard (or the Mac's, in the simulator) types straight in.
struct SearchView: View {
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @State private var query = ""
    @State private var searched = ""          // the term the results are for
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var layout: KeyboardLayout = Localizer.shared.language == .uk ? .ukrainian : .english
    @FocusState private var focusedKey: String?
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: LibrarySearchResults {
        LibrarySearchResults(query: term, library: catalog.library.map { catalog.resolved(libraryItem($0)) },
                             torrents: searched == term ? items.map { catalog.resolved($0) } : [])
    }
    private var noResults: Bool {
        term.count >= 2 && !loading && !catalog.libraryLoading && error == nil && catalog.libraryError == nil &&
        results.library.isEmpty && results.torrents.isEmpty && (!config.searchEnabled || searched == term)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 28) {
                queryLine
                SearchKeyboard(layout: $layout, focusedKey: $focusedKey, type: { query += $0 },
                               delete: { if !query.isEmpty { query.removeLast() } })
            }
            .frame(width: 600)
            .padding(.top, 158)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if term.count < 2 {
                        if let popular = catalog.rows["popular"], !popular.isEmpty {
                            Text(L("Popular now")).font(.system(size: 32, weight: .bold))
                            FilmGrid(items: Array(popular.prefix(24)), api: api, config: config) { _ in cardFocused() }
                        } else if catalog.loading.contains("popular") {
                            LoadingState(text: L("Loading titles…"), minHeight: 600)
                        }
                    } else {
                        if !results.library.isEmpty {
                            Label(L("In your library"), systemImage: "folder").font(.system(size: 32, weight: .bold))
                            FilmGrid(items: results.library, api: api, config: config) { _ in cardFocused() }
                        }
                        if let libraryError = catalog.libraryError {
                            ErrorPanel(message: libraryError) { Task { await catalog.loadLibrary(api: api) } }
                        }
                        if config.searchEnabled && !noResults {
                            Label(L("Torrents"), systemImage: "network").font(.system(size: 32, weight: .bold))
                            if let error {
                                ErrorPanel(message: error) { Task { await search(term) } }
                            } else if loading || searched != term {
                                LoadingState(text: L("Searching…"), minHeight: 180)
                            } else if !results.torrents.isEmpty {
                                FilmGrid(items: results.torrents, api: api, config: config) { _ in cardFocused() }
                            } else if !results.library.isEmpty {
                                Text(L("No additional torrent titles.")).foregroundStyle(.secondary)
                            }
                        }
                        if noResults {
                            VStack(spacing: 24) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 64, weight: .light)).foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(L("No results for “%@”", term))
                                    .font(.system(size: 32, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("search-empty")
                                Text(L("Check the spelling or try a new search."))
                                    .font(.system(size: 24)).foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity, minHeight: 520)
                        }
                        if !config.searchEnabled {
                            Text(L("Searching your library. Torrent search is disabled on this server.")).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 158)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity)
            .scrollClipDisabled()
            .tvScrollEdge()
            .focusSection()
        }
        .padding(.horizontal, TVLayout.edge).padding(.top, ScreenLayout.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .horizontal)
        .defaultFocus($focusedKey, layout.letters.first.map(String.init), priority: .userInitiated)
        // A hardware keyboard types and deletes wherever the focus is.
        .onKeyPress(phases: .down) { press in
            if press.key == .delete { if !query.isEmpty { query.removeLast() }; return .handled }
            let text = press.characters.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "'" || $0 == "-" }
            guard !text.isEmpty else { return .ignored }
            query += text.lowercased()
            return .handled
        }
        .task(id: term) {
            guard term.count >= 2 else { items = []; searched = ""; error = nil; loading = false; return }
            searched = ""
            guard config.searchEnabled else { items = []; loading = false; error = nil; return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }  // typing pause
            await search(term)
        }
        .task { await catalog.loadLibrary(api: api) }
        .task { await catalog.loadFeed("popular", api: api, config: config) }
        .onChange(of: focusedKey) { _, key in if key != nil { keyboardVisited = true } }
        .onAppear { UserDefaults.standard.removeObject(forKey: "recentSearches") }
        .onDisappear { keyboardVisited = false }
    }
    /// Down from the tab bar lands under the Search tab - in the results, on
    /// the right. The first time focus arrives there, it goes to the keyboard
    /// instead, where typing begins. Later moves into the results stay.
    @State private var keyboardVisited = false
    private func cardFocused() {
        guard !keyboardVisited else { return }
        keyboardVisited = true
        focusedKey = layout.letters.first.map(String.init)
    }
    private var queryLine: some View {
        Text(query.isEmpty ? L("Search") : query)
            .font(.system(size: 34, weight: .semibold))
            .lineLimit(1).truncationMode(.head)
            .foregroundStyle(focusedKey == "search-input" ? .black : .white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(focusedKey == "search-input" ? Color.white : Color.white.opacity(0.08), in: Capsule())
            .focusable()
            .focused($focusedKey, equals: "search-input")
            .accessibilityIdentifier("search-query")
    }
    private func search(_ text: String) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: text)])
            try Task.checkCancellation()
            guard text == term else { return }
            items = result.results
            searched = text
            await catalog.enrich(Array(items.prefix(12)), api: api, config: config)
        } catch is CancellationError {} catch { self.error = error.localizedDescription; searched = text }
    }

}

enum KeyboardLayout: Equatable {
    case ukrainian, english, digits
    var letters: [Character] {
        switch self {
        case .ukrainian: Array("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'")
        case .english: Array("abcdefghijklmnopqrstuvwxyz")
        case .digits: Array("1234567890-.:&!?")
        }
    }
}

/// The on-screen keys: a letter grid, then space, delete, digits and the
/// language switch. Pressing a key never moves focus.
struct SearchKeyboard: View {
    @Binding var layout: KeyboardLayout
    var focusedKey: FocusState<String?>.Binding
    let type: (String) -> Void
    let delete: () -> Void
    @State private var lastLetters: KeyboardLayout = .ukrainian
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 14), count: 6), spacing: 12) {
                ForEach(layout.letters, id: \.self) { letter in
                    key(String(letter), id: String(letter)) { type(String(letter)) }
                }
            }
            HStack(spacing: 14) {
                // As wide as the letter grid: 6 x 88 + 5 x 14 = 598 = 216 + 120 + 110 + 110 + 3 x 14.
                key(L("Space"), id: "space", width: 216) { type(" ") }
                key(nil, icon: "delete.left", id: "delete", width: 120) { delete() }
                    .accessibilityLabel(L("Delete"))
                key(layout == .digits ? (lastLetters == .ukrainian ? "АБВ" : "ABC") : "123", id: "digits", width: 110) {
                    if layout == .digits { layout = lastLetters } else { lastLetters = layout; layout = .digits }
                }
                key(layout == .english || (layout == .digits && lastLetters == .english) ? "УКР" : "ENG", id: "language", width: 110) {
                    let next: KeyboardLayout = (layout == .digits ? lastLetters : layout) == .ukrainian ? .english : .ukrainian
                    lastLetters = next; layout = next
                }
                .accessibilityLabel(L("Keyboard language"))
            }
        }
        .focusSection()
        .onAppear { if layout != .digits { lastLetters = layout } }
    }
    private func key(_ title: String?, icon: String? = nil, id: String, width: CGFloat = 88, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon { Image(systemName: icon) } else { Text(title ?? "") }
            }
            .font(.system(size: title.map { $0.count > 1 } ?? false ? 22 : 30, weight: .medium))
            .frame(width: width, height: 64)
        }
        .buttonStyle(KeyStyle())
        .focused(focusedKey, equals: id)
        .accessibilityIdentifier("key-\(id)")
    }
    struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Label(content: configuration.label, pressed: configuration.isPressed) }
        struct Label<Content: View>: View {
            let content: Content
            let pressed: Bool
            @Environment(\.isFocused) private var focused
            var body: some View {
                content
                    .foregroundStyle(focused ? .black : .white)
                    .background(focused ? Color.white.opacity(pressed ? 0.75 : 1) : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .scaleEffect(focused ? 1.1 : 1)
                    .animation(.easeOut(duration: 0.12), value: focused)
            }
        }
    }
}

/// A spinner in the middle of the space it is given - never in a corner.
struct LoadingState: View {
    let text: String
    var minHeight: CGFloat = 400
    var body: some View {
        ProgressView(text).frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

struct ErrorPanel: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            Button(L("Try again"), action: retry)
        }.padding(.vertical, 15)
    }
}

struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backID = UUID()
    @FocusState private var backFocused: Bool
    private var license: String {
        guard let url = Bundle.main.url(forResource: "VLCKit-COPYING", withExtension: "txt") else { return L("License file unavailable.") }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? L("License file unavailable.")
    }
    private var paragraphs: [String] {
        license.components(separatedBy: "\n\n").map {
            $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }.filter { !$0.isEmpty }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Player licenses"))
                        .font(.system(size: 50, weight: .bold))
                        .accessibilityIdentifier("license-heading")
                    Text("VideoLAN TVVLCKit 3.7.2")
                        .font(.system(size: 28, weight: .semibold))
                    Text(L("Playback uses VideoLAN’s VLCKit library. Source: %@", "https://code.videolan.org/videolan/VLCKit"))
                        .font(.system(size: 22)).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text(verbatim: paragraph)
                            .font(.system(size: index == 0 ? 28 : 24, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(index == 0 ? 1 : 0.85))
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .focusable()
                    }
                }
                .padding(36)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .padding(.horizontal, TVLayout.edge)
            .padding(.top, 198).padding(.bottom, 70)
            .frame(maxWidth: .infinity)
        }
        .tvScrollEdge()
        .ignoresSafeArea(edges: .horizontal)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            Button { dismiss() } label: { Label(L("Back"), systemImage: "chevron.left") }
                .buttonStyle(TVNavigationButtonStyle(selected: false, iconOnly: false))
                .padding(6).modifier(TVNavigationGlass())
                .focused($backFocused)
                .accessibilityIdentifier("license-back")
                .padding(.top, 104)
                .frame(maxWidth: .infinity)
        }
        .defaultFocus($backFocused, true)
        .preference(key: BackDismissPreference.self, value: [BackScrollAction(id: backID, scroll: { dismiss() })])
        .onExitCommand { dismiss() }
    }
}

/// Wide, left-aligned rows keep long media names readable from the sofa.
struct TVSelectionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(content: configuration.label, pressed: configuration.isPressed)
    }
    private struct Row<Content: View>: View {
        let content: Content
        let pressed: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            content
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34).padding(.vertical, 24)
                .foregroundStyle(focused ? .black : .white)
                .background(focused ? Color.white.opacity(pressed ? 0.8 : 1) : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .scaleEffect(focused ? 1.015 : 1.0)
                .shadow(color: focused ? Color.black.opacity(0.35) : Color.clear, radius: 14, y: 6)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}


/// A person's page: their photo and name, then every film and show they are in.
struct PersonView: View {
    let route: PersonRoute
    let api: TorrentTubeAPI
    let config: ServerConfig
    @State private var credits: PersonCredits?
    @State private var error: String?
    @State private var retry = 0
    @State private var scrolled = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                HStack(spacing: 30) {
                    ZStack {
                        Circle().fill(Color(white: 0.14))
                        if let photo = credits?.photo ?? route.photo, let url = URL(string: photo) {
                            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                        } else {
                            Text(String(route.name.prefix(1))).font(.system(size: 64, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        }
                    }.frame(width: 180, height: 180).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(route.name).font(.system(size: 50, weight: .bold))
                        if let credits, !credits.titles.isEmpty {
                            Text(L("%ld titles", credits.titles.count)).font(.system(size: 26)).foregroundStyle(.secondary)
                        }
                    }
                }
                if let credits {
                    if credits.titles.isEmpty {
                        ContentUnavailableView(L("Nothing here yet"), systemImage: "film").frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        FilmGrid(items: credits.items, api: api, config: config)
                    }
                } else if let error {
                    ErrorPanel(message: error) { retry += 1 }
                } else {
                    LoadingState(text: L("Loading titles…"), minHeight: 500)
                }
            }.padding(.horizontal, TVLayout.edge).padding(.top, 118 + 40).padding(.bottom, 70)
        }
        // Content melts into the bar; the name moves up beside it once the big one scrolls away.
        .tvScrollEdge(150)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 170 } action: { _, new in scrolled = new }
        .ignoresSafeArea(edges: .horizontal)
        .overlay(alignment: .top) {
            // Beside the navigation panel, at the same top edge.
            Text(route.name).font(.system(size: 26, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                .frame(width: 350, height: 74, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TVLayout.edge).padding(.top, 14)
                .accessibilityIdentifier("person-floating-name")
                .opacity(scrolled ? 1 : 0).animation(.easeOut(duration: 0.2), value: scrolled)
        }
        .task(id: retry) {
            error = nil
            do { credits = try await api.request("api/person", query: [.init(name: "id", value: String(route.id))]) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
