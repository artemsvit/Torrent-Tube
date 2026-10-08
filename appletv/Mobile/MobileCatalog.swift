import SwiftUI

enum MobileStyle {
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.2)
}

/// One side margin for a whole screen: 16 on iPhone, 32 on iPad - hero text,
/// shelf titles and the first poster all start on it.
private struct MobileEdgeKey: EnvironmentKey { static let defaultValue: CGFloat = 16 }
extension EnvironmentValues {
    var mobileEdge: CGFloat {
        get { self[MobileEdgeKey.self] }
        set { self[MobileEdgeKey.self] = newValue }
    }
}

/// "Movie", "TV Show", "Cartoon" or "Animated Series" - the eyebrow over a title.
func mobileKind(_ item: MediaItem, _ details: Details?) -> String? {
    let type = details?.mediaType ?? item.mediaType
    if details?.kind == "Cartoon" { return type == "tv" ? L("Animated Series") : L("Cartoon") }
    switch type {
    case "tv": return L("TV Show")
    case "movie": return L("Movie")
    default: return nil
    }
}

struct MobileArtwork: View {
    let url: String?
    var ratio: CGFloat = 2 / 3
    var fit = false
    var body: some View {
        Color(white: 0.12).aspectRatio(ratio, contentMode: .fit)
            .overlay {
                AsyncImage(url: url.map { higherResolution($0, backdrop: ratio > 1) }.flatMap(URL.init(string:))) { image in
                    if fit { image.resizable().scaledToFit() }
                    else { image.resizable().scaledToFill() }
                } placeholder: {
                    Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// An image filling its frame from the top - the hero backdrops.
struct MobileBackdrop: View {
    let url: String?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.08)
                if let url, let address = URL(string: higherResolution(url, backdrop: true)) {
                    AsyncImage(url: address) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .clipped()
                }
            }
        }.accessibilityHidden(true)
    }
}

/// Rating with a golden star, year and length - one line under a title.
struct MobileFacts: View {
    let item: MediaItem
    let details: Details?
    var body: some View {
        HStack(spacing: 10) {
            if let rating = item.rating, rating > 0 {
                Label { Text(String(format: "%.1f", rating)).fontWeight(.semibold) } icon: {
                    Image(systemName: "star.fill").foregroundStyle(MobileStyle.gold)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.16), in: Capsule())
            }
            if let certification = details?.certification, !certification.isEmpty {
                Text(certification).font(.caption.bold())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.6), lineWidth: 1))
            }
            Text(facts.joined(separator: " · ")).lineLimit(1)
        }
        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
    }
    private var facts: [String] {
        var list: [String] = []
        if let year = details?.year, !year.isEmpty { list.append(year) }
        if let runtime = details?.runtime, runtime > 0 { list.append(runtime >= 60 ? L("%ld h %ld min", runtime / 60, runtime % 60) : L("%ld min", runtime)) }
        if let genres = details?.genres, !genres.isEmpty { list.append(genres.prefix(2).joined(separator: ", ")) }
        return list
    }
}

struct MobileCard: View {
    let item: MediaItem
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(MobileContext.self) private var context
    var body: some View {
        let value = catalog.resolved(item)
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 8) {
                MobileArtwork(url: value.poster)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)) }
                    .overlay(alignment: .topTrailing) {
                        if favorites.contains(value, server: context.api.baseURL) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.55), in: Circle()).padding(6)
                        }
                    }
                Text(value.displayTitle).font(.subheadline.weight(.medium)).lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.primary).multilineTextAlignment(.leading)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(value.displayTitle)
        .contextMenu {
            let saved = favorites.contains(value, server: context.api.baseURL)
            Button {
                Task {
                    // Its details decide the Favorites tab: movie, show or cartoon.
                    if !saved { await catalog.loadDetails(item, api: context.api, config: context.config) }
                    favorites.toggle(value, details: catalog.details[item.title], server: context.api.baseURL)
                }
            } label: {
                Label(saved ? L("Remove from Favorites") : L("Add to Favorites"), systemImage: saved ? "heart.slash" : "heart")
            }
        }
        .task(id: item.id) { await catalog.enrich([item], api: context.api, config: context.config) }
    }
}

/// What every catalog view needs from the connected server.
@Observable final class MobileContext {
    let api: TorrentTubeAPI
    let config: ServerConfig
    init(api: TorrentTubeAPI, config: ServerConfig) { self.api = api; self.config = config }
}

struct MobileGrid: View {
    @Environment(\.mobileEdge) private var edge
    let items: [MediaItem]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        // Three posters across an iPhone, more on an iPad.
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 220 : (sizeClass == .regular ? 160 : 104)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 240), spacing: 14)], alignment: .leading, spacing: 22) {
            ForEach(items) { MobileCard(item: $0) }
        }.padding(.horizontal, edge)
    }
}

struct MobileShelf: View {
    @Environment(\.mobileEdge) private var edge
    let title: String
    let items: [MediaItem]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 128
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal, edge)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { MobileCard(item: $0).frame(width: min(cardWidth * (sizeClass == .regular ? 1.3 : 1), 240)) }
                }.padding(.horizontal, edge)
            }.scrollIndicators(.hidden)
        }
    }
}

/// Category tabs inside a screen - one capsule each, the current one filled.
struct MobileChips: View {
    @Environment(\.mobileEdge) private var edge
    let options: [(String, String)]
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { key, label in
                    let current = selected == key
                    Button { withAnimation(.snappy) { selected = key } } label: {
                        Text(L(label)).font(.subheadline.weight(current ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(current ? .black : .white)
                            .background(current ? Color.white : Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(current ? .isSelected : [])
                    .accessibilityIdentifier("chip-\(key)")
                }
            }.padding(.horizontal, edge)
        }.scrollIndicators(.hidden)
    }
}

struct MobileError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L("Try again"), action: retry).buttonStyle(.bordered).frame(minHeight: 44)
        }.frame(maxWidth: .infinity).padding()
    }
}

/// A spinner in the middle of the space - never in a corner.
struct MobileLoading: View {
    let text: String
    var body: some View { ProgressView(text).frame(maxWidth: .infinity, minHeight: 280) }
}

struct MobileHome: View {
    @Environment(\.mobileEdge) private var edge
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(ResumeHistory.self) private var history
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("showContinueWatching") private var showContinue = true
    @State private var playback: PlaybackRequest?
    @State private var serverNotice = false
    private let feeds = [("new", "New to explore"), ("popular", "Popular now"), ("movies", "Movies"), ("tv", "TV Shows"), ("cartoons", "Cartoons"), ("ukrainian", "Ukrainian")]
    private var featured: MediaItem? { (catalog.rows["new"]?.first ?? catalog.library.first.map(libraryItem)).map(catalog.resolved) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let featured { hero(featured) }
                else if catalog.loading.contains("new") || catalog.libraryLoading { MobileLoading(text: L("Finding something to watch…")).padding(.top, 120) }
                if showContinue { continueWatching }
                ForEach(feeds, id: \.0) { feed, title in
                    if let items = catalog.rows[feed], !items.isEmpty {
                        MobileShelf(title: L(title), items: Array(items.prefix(24)))
                    } else if let error = catalog.errors[feed] {
                        MobileError(message: "\(L(title)): \(error)") { Task { await catalog.loadFeed(feed, api: api, config: config, refresh: true) } }
                    }
                }
                if !catalog.library.isEmpty {
                    MobileShelf(title: L("New on your server"), items: catalog.library.prefix(24).map(libraryItem))
                }
                if let error = catalog.libraryError { MobileError(message: error) { Task { await catalog.loadLibrary(api: api) } } }
                if !config.searchEnabled, catalog.library.isEmpty, !catalog.libraryLoading, catalog.libraryError == nil {
                    ContentUnavailableView(L("Your library is empty"), systemImage: "film", description: Text(L("Titles on your server will appear here.")))
                        .frame(maxWidth: .infinity)
                }
            }.padding(.bottom, 24)
        }
        // The hero runs under the status bar, like the Apple TV app.
        .ignoresSafeArea(edges: .top)
        .refreshable { await load(refresh: true) }
        .task { await load(refresh: false) }
        .task(id: featured?.id) { if let featured { await catalog.loadDetails(featured, api: api, config: config) } }
        .fullScreenCover(item: $playback) { MobilePlayback(request: $0, api: api) }
        .alert(L("Streaming unavailable"), isPresented: $serverNotice) { Button(L("OK"), role: .cancel) {} } message: {
            Text(L("Update Torrent Tube on your server to stream on this device."))
        }
    }
    private func hero(_ item: MediaItem) -> some View {
        let details = catalog.details[item.title]
        let height: CGFloat = sizeClass == .regular ? 620 : 560
        return ZStack(alignment: .bottomLeading) {
            MobileBackdrop(url: details?.backdrop ?? item.poster)
            LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.25),
                                   .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.85), location: 0.8),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                if let kind = mobileKind(item, details) {
                    Text(kind.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(.white.opacity(0.65))
                }
                Text(details?.title ?? item.displayTitle).font(.system(size: sizeClass == .regular ? 48 : 34, weight: .heavy))
                    .lineLimit(2).minimumScaleFactor(0.7)
                MobileFacts(item: item, details: details)
                if let overview = details?.overview ?? item.overview, !overview.isEmpty {
                    Text(overview).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(3)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                HStack(spacing: 10) {
                    Button {
                        if config.supportsPlayback {
                            playback = PlaybackRequest(source: item.source, title: item.displayTitle,
                                                       artwork: details?.backdrop ?? item.poster, tmdbID: details?.tmdbId ?? item.tmdbId)
                        } else { serverNotice = true }
                    } label: {
                        Label(L("Play"), systemImage: "play.fill").font(.headline).frame(maxWidth: 220, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .accessibilityIdentifier("hero-play")
                    NavigationLink(value: item) {
                        Label(L("Details"), systemImage: "info.circle").font(.headline).frame(minHeight: 34)
                    }
                    .buttonStyle(.bordered).tint(.white)
                    .accessibilityIdentifier("featured-details")
                }.padding(.top, 6)
            }
            .padding(.horizontal, edge).padding(.bottom, 8)
        }
        .frame(height: height).clipped()
    }
    @ViewBuilder private var continueWatching: some View {
        let entries = history.entries.filter { $0.server == api.baseURL.absoluteString }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Continue Watching")).font(.title3.bold()).padding(.horizontal, edge)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { entry in
                            Button { playback = PlaybackRequest(source: entry.source, title: entry.title, artwork: entry.artwork) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    MobileArtwork(url: entry.artwork, ratio: 16 / 9)
                                        .overlay(alignment: .bottom) {
                                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).frame(height: 44)
                                        }
                                        .overlay(alignment: .bottomLeading) {
                                            ProgressView(value: min(entry.seconds, entry.duration), total: max(1, entry.duration)).tint(.white)
                                                .padding(.horizontal, 10).padding(.bottom, 8)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(L("Resume at %@", entry.displayPosition)).font(.caption).foregroundStyle(.secondary)
                                }.frame(width: 250).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, edge)
                }.scrollIndicators(.hidden)
            }
        }
    }
    private func load(refresh: Bool) async {
        await catalog.loadLibrary(api: api)
        await catalog.loadFeed("new", api: api, config: config, refresh: refresh)
        await withTaskGroup(of: Void.self) { group in
            for (feed, _) in feeds.dropFirst() { group.addTask { await catalog.loadFeed(feed, api: api, config: config, refresh: refresh) } }
        }
    }
}

/// Movies or TV Shows: chips for the sub-categories, then a poster grid.
struct MobileCategory: View {
    let options: [(String, String)]
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @State private var selected: String
    init(options: [(String, String)], api: TorrentTubeAPI, config: ServerConfig) {
        self.options = options; self.api = api; self.config = config
        _selected = State(initialValue: options.first?.0 ?? "movies")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if options.count > 1 { MobileChips(options: options, selected: $selected) }
                let items = selected == "library" ? catalog.library.map(libraryItem) : (catalog.rows[selected] ?? [])
                if items.isEmpty && (catalog.loading.contains(selected) || (selected == "library" && catalog.libraryLoading)) {
                    MobileLoading(text: L("Loading titles…"))
                } else if let error = selected == "library" ? catalog.libraryError : catalog.errors[selected] {
                    MobileError(message: error) { Task { await load(refresh: true) } }
                } else if items.isEmpty {
                    ContentUnavailableView(L("Nothing here yet"), systemImage: "film", description: Text(L("Try another category or refresh your server’s catalog.")))
                        .frame(maxWidth: .infinity)
                }
                MobileGrid(items: items)
            }.padding(.vertical, 8)
        }
        .refreshable { await load(refresh: true) }
        .task(id: selected) { await load(refresh: false) }
    }
    private func load(refresh: Bool) async {
        if selected == "library" { await catalog.loadLibrary(api: api) }
        else { await catalog.loadFeed(selected, api: api, config: config, refresh: refresh) }
    }
}

/// Медіатека: what is already on the server (one chip per type, newest
/// first) and Favorites (grouped by type) - as on Apple TV.
struct MobileLibrary: View {
    let api: TorrentTubeAPI
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.mobileEdge) private var edge
    @State private var section = ""
    var body: some View {
        let active = section.isEmpty ? LibrarySections.defaultSection(catalog.library) : section
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MobileChips(options: LibrarySections.chips(catalog.library, favorites: favorites.entries(server: api.baseURL).count),
                            selected: Binding(get: { active }, set: { section = $0 }))
                if active == "favorites" {
                    let all = favorites.entries(server: api.baseURL)
                    if all.isEmpty {
                        ContentUnavailableView(L("No favorites yet"), systemImage: "heart", description: Text(L("Tap the heart on a title to save it here.")))
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(LibrarySections.kinds, id: \.0) { kind, label in
                        let group = all.filter { $0.kind == kind }
                        if !group.isEmpty {
                            Text(L(label)).font(.title3.bold()).padding(.horizontal, edge).padding(.top, 6)
                            MobileGrid(items: group.map(\.item))
                        }
                    }
                } else {
                    let items = catalog.library.filter { $0.kind == active }
                    if items.isEmpty && catalog.libraryLoading {
                        MobileLoading(text: L("Loading titles…"))
                    } else if let error = catalog.libraryError, items.isEmpty {
                        MobileError(message: error) { Task { await catalog.loadLibrary(api: api) } }
                    } else if items.isEmpty {
                        ContentUnavailableView(L("Nothing here yet"), systemImage: "externaldrive",
                                               description: Text(L("Titles you download to the server appear here.")))
                            .frame(maxWidth: .infinity)
                    }
                    MobileGrid(items: items.map(libraryItem))
                }
            }.padding(.vertical, 8)
        }
        .refreshable { await catalog.loadLibrary(api: api) }
        .task {
            await catalog.loadLibrary(api: api)
            // The server is still matching titles: show them as they come in.
            while catalog.libraryPending > 0 && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                await catalog.loadLibrary(api: api)
            }
        }
    }
}

struct MobileSearch: View {
    @Environment(\.mobileEdge) private var edge
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @AppStorage("recentSearches") private var recent = ""
    @State private var query = ""
    @State private var items: [MediaItem] = []
    @State private var searched = ""
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recentTerms: [String] { recent.split(separator: "\n").map(String.init) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !config.searchEnabled {
                    ContentUnavailableView(L("Search unavailable"), systemImage: "magnifyingglass", description: Text(L("Enable search on your server to discover more titles.")))
                        .frame(maxWidth: .infinity)
                } else if term.count < 2 {
                    if !recentTerms.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L("Recent searches")).font(.title3.bold())
                                Spacer()
                                Button(L("Clear")) { recent = "" }.font(.subheadline)
                            }.padding(.horizontal, edge)
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(recentTerms, id: \.self) { text in
                                        Button { query = text } label: {
                                            Label(text, systemImage: "clock.arrow.circlepath").font(.subheadline)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(.white.opacity(0.12), in: Capsule())
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, edge)
                            }.scrollIndicators(.hidden)
                        }
                    }
                    if let popular = catalog.rows["popular"], !popular.isEmpty {
                        Text(L("Popular now")).font(.title3.bold()).padding(.horizontal, edge)
                        MobileGrid(items: Array(popular.prefix(24)))
                    }
                } else if let error {
                    MobileError(message: error) { retry += 1 }
                } else if loading && searched != term {
                    MobileLoading(text: L("Searching…"))
                } else if items.isEmpty {
                    ContentUnavailableView(L("No results for “%@”", term), systemImage: "magnifyingglass",
                                           description: Text(L("Check the spelling or try a new search.")))
                        .frame(maxWidth: .infinity)
                } else {
                    Text(L("Results for “%@”", searched)).font(.title3.bold()).padding(.horizontal, edge)
                    MobileGrid(items: items)
                }
            }.padding(.vertical, 8)
        }
        .searchable(text: $query, prompt: Text(L("Search")))
        .onSubmit(of: .search) { remember() }
        .task { await catalog.loadFeed("popular", api: api, config: config) }
        .task(id: "\(term)|\(retry)") {
            guard config.searchEnabled, term.count >= 2 else { items = []; error = nil; searched = ""; return }
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(400))  // typing pause
                let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: term)])
                try Task.checkCancellation()
                items = result.results; searched = term; loading = false
                await catalog.enrich(Array(items.prefix(24)), api: api, config: config)
            } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = error.localizedDescription; loading = false }
            }
        }
    }
    private func remember() {
        guard term.count >= 2 else { return }
        recent = ([term] + recentTerms.filter { $0.caseInsensitiveCompare(term) != .orderedSame }).prefix(8).joined(separator: "\n")
    }
}
