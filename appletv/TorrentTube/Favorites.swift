import SwiftUI

struct FavoritePosterBadge: View {
    let item: MediaItem
    let server: URL
    @Environment(FavoritesStore.self) private var favorites
    var body: some View {
        if favorites.contains(item, server: server) {
            Image(systemName: "heart.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .padding(10).background(.black.opacity(0.55), in: Circle()).padding(12)
                .accessibilityHidden(true).allowsHitTesting(false)
        }
    }
}

/// The heart on a title page.
struct FavoriteButton: View {
    let item: MediaItem
    let details: Details?
    let server: URL
    @Environment(FavoritesStore.self) private var favorites
    var body: some View {
        let saved = favorites.contains(item, server: server)
        Button { favorites.toggle(item, details: details, server: server) } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
        }
        .buttonStyle(.bordered).tint(.white)
        .accessibilityLabel(saved ? L("Remove from Favorites") : L("Add to Favorites"))
        .accessibilityIdentifier("favorite-toggle")
    }
}

/// Медіатека: what is already on the server (one chip per type, newest
/// first) and Favorites (newest first). The same screen on
/// Apple TV, iPad and iPhone.
struct LibraryView: View {
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Binding var section: String
    let chipFocus: FocusState<String?>.Binding
    let scrollRequest: UUID
    private static let top = "library-top"
    var body: some View {
        let active = section.isEmpty ? LibrarySections.defaultSection(catalog.library) : section
        ScrollViewReader { proxy in
        ScrollView {
            // The very top of the page, above its padding: scrolling here shows
            // the heading below the bar, where it starts.
            VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0).id(Self.top)
            VStack(alignment: .leading, spacing: 35) {
                Text(L("Library")).font(.system(size: 50, weight: .bold)).accessibilityIdentifier("library-heading")
                // The Library syncs itself (new titles only); Settings has "Sync now".
                ChipRow(options: LibrarySections.chips(catalog.library, favorites: favorites.entries(server: api.baseURL).count),
                        selected: active, select: { section = $0 }, externalFocus: chipFocus)
                if active == "favorites" {
                    favoritesSection
                } else if active == "collections" {
                    collectionsSection
                } else {
                    let items = catalog.library.filter { $0.kind == active }
                    if items.isEmpty && catalog.libraryLoading {
                        LoadingState(text: L("Loading titles…"), minHeight: 600)
                    } else if let error = catalog.libraryError, items.isEmpty {
                        ErrorPanel(message: error) { Task { await catalog.loadLibrary(api: api) } }
                    } else if items.isEmpty {
                        ContentUnavailableView(L("Nothing here yet"), systemImage: "externaldrive",
                                               description: Text(L("Titles you download to the server appear here.")))
                            .frame(maxWidth: .infinity, minHeight: 500)
                    }
                    FilmGrid(items: items.map(libraryItem), api: api, config: config)
                }
            }.padding(.horizontal, TVLayout.edge).padding(.top, 158 + ScreenLayout.top).padding(.bottom, 70)
            }
        }
        // A shorter list (Movies, then Favorites) kept the old offset and the
        // focused chip's place on screen, so each switch pushed the page
        // further down, past its top. Keep the top fixed and go back to it.
        .tvScrollEdge()
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .onChange(of: section) { _, _ in
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(Self.top, anchor: .top) }
        }
        .onChange(of: scrollRequest) { _, _ in
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(Self.top, anchor: .top)
                chipFocus.wrappedValue = active
            }
        }
        .onAppear {
            // Returning from a title goes directly to its Library category.
            // Do not restore the poster and then move focus again on Back.
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(Self.top, anchor: .top)
                chipFocus.wrappedValue = active
            }
        }
        .defaultFocus(chipFocus, active, priority: .userInitiated)
        }
        .ignoresSafeArea(edges: .horizontal)
        .task {
            favorites.sync()
            await catalog.loadLibrary(api: api)
            // The server is still matching titles: show them as they come in.
            while catalog.libraryPending > 0 && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                await catalog.loadLibrary(api: api)
            }
            await catalog.syncLibrary(api: api, config: config)  // saves only titles not saved yet
        }
    }
    @ViewBuilder private var collectionsSection: some View {
        let all = LibrarySections.collections(catalog.library)
        if all.isEmpty {
            ContentUnavailableView(L("No collections yet"), systemImage: "square.stack",
                                   description: Text(L("Films of one series, like Harry Potter, appear here once two of them are on the server.")))
                .frame(maxWidth: .infinity, minHeight: 500)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 36)], alignment: .leading, spacing: 36) {
            ForEach(all) { CollectionCard(collection: $0) }
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).focusSection()
    }
    @ViewBuilder private var favoritesSection: some View {
        let all = favorites.entries(server: api.baseURL)
        if all.isEmpty {
            ContentUnavailableView(L("No favorites yet"), systemImage: "heart",
                                   description: Text(L("Press the heart on a title page, or hold Select on a poster, to keep it here.")))
                .frame(maxWidth: .infinity, minHeight: 500)
        }
        // One grid, newest first - like the other chips and the web page.
        FilmGrid(items: all.map(\.item), api: api, config: config)
    }
}

/// A collection in the Library: its poster with the films stacked behind it.
struct CollectionCard: View {
    let collection: LibraryCollection
    @FocusState private var focused: Bool
    var body: some View {
        NavigationLink(value: collection) {
            VStack(alignment: .leading, spacing: 14) {
                ArtworkView(url: collection.poster, seed: collection.name).aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 3 : 1) }
                    .overlay(alignment: .topLeading) {
                        Label("\(collection.titles.count)", systemImage: "square.stack.fill").font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.6), in: Capsule()).padding(12)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name).font(.system(size: 21, weight: .semibold)).lineLimit(2)
                    Text(collection.count).font(.system(size: 18)).opacity(0.7)
                }
                .foregroundStyle(focused ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading).padding(.horizontal, 4)
            }
        }
        .buttonStyle(CinemaCardStyle()).focused($focused)
        .accessibilityLabel("\(collection.name), \(collection.count)").accessibilityIdentifier("collection-\(collection.id)")
    }
}

/// A collection's page: name, count and overview on the left over a dim
/// backdrop, then its films in release order in six fixed columns, each
/// with its part and year above its title. Focus in the first row keeps the
/// page at its top, so the heading never slides under the bar.
struct CollectionView: View {
    let collection: LibraryCollection
    let api: TorrentTubeAPI
    let config: ServerConfig
    private static let top = "collection-top"
    private static let columns = 6
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.top)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(collection.name).font(.system(size: 50, weight: .bold)).lineLimit(1)
                        Text(collection.count).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        if let overview = collection.info.overview, !overview.isEmpty {
                            Text(overview).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8)).lineSpacing(4).lineLimit(3)
                                .frame(maxWidth: 1180, alignment: .leading).padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 36, alignment: .top), count: Self.columns),
                              alignment: .leading, spacing: 44) {
                        ForEach(Array(collection.titles.enumerated()), id: \.element.id) { index, title in
                            CollectionFilmCard(title: title) {
                                // The first row: back to the very top, heading in view.
                                guard index < Self.columns else { return }
                                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.top, anchor: .top) }
                            }
                        }
                    }
                    .padding(.top, 40).focusSection()
                }
                .padding(.horizontal, TVLayout.edge).padding(.top, 158).padding(.bottom, 70)
            }
            .tvScrollEdge(150)
            .ignoresSafeArea(edges: .horizontal)
        }
        .background(alignment: .top) {
            if let backdrop = collection.info.backdrop {
                ArtworkView(url: backdrop, background: true, fill: true).frame(height: 700)
                    .opacity(0.35)
                    .mask(LinearGradient(colors: [.white, .white.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
            }
        }
    }
}

/// A film in a collection: its poster, its part and year, then its title -
/// the same height in every column.
private struct CollectionFilmCard: View {
    let title: LibraryTitle
    let onFocus: () -> Void
    @Environment(CatalogStore.self) private var catalog
    @FocusState private var focused: Bool
    var body: some View {
        let item = libraryItem(title)
        let value = catalog.resolved(item)
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 12) {
                ArtworkView(url: value.poster, seed: value.displayTitle).aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 3 : 1) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(LibraryCollection.line(title)).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Text(value.displayTitle).font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(focused ? .white : .white.opacity(0.7)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }
        .buttonStyle(CinemaCardStyle()).focused($focused)
        .onChange(of: focused) { _, now in if now { onFocus() } }
        .accessibilityLabel("\(value.displayTitle), \(LibraryCollection.line(title))")
    }
}
