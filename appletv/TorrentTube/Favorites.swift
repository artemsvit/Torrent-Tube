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
