import SwiftUI

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
/// first) and Favorites (grouped by type, newest first). The same screen on
/// Apple TV, iPad and iPhone.
struct LibraryView: View {
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @State private var section = ""
    var body: some View {
        let active = section.isEmpty ? LibrarySections.defaultSection(catalog.library) : section
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                Text(L("Library")).font(.system(size: 50, weight: .bold)).accessibilityIdentifier("library-heading")
                // The Library syncs itself (new titles only); Settings has "Sync now".
                ChipRow(options: LibrarySections.chips(catalog.library, favorites: favorites.entries(server: api.baseURL).count),
                        selected: active) { section = $0 }
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
        .tvScrollEdge()
        .ignoresSafeArea(edges: .horizontal)
        .task {
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
        // Grouped by type, each group newest first.
        ForEach(LibrarySections.kinds, id: \.0) { kind, label in
            let group = all.filter { $0.kind == kind }
            if !group.isEmpty {
                Text(L(label)).font(.system(size: 32, weight: .bold)).padding(.top, 10)
                FilmGrid(items: group.map(\.item), api: api, config: config)
            }
        }
    }
}
