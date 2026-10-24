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

/// A collection's page: its backdrop, poster, name and overview, then its
/// films in release order, each with its part and year.
struct CollectionView: View {
    let collection: LibraryCollection
    let api: TorrentTubeAPI
    let config: ServerConfig
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                HStack(alignment: .bottom, spacing: 48) {
                    ArtworkView(url: collection.poster, seed: collection.name).aspectRatio(2.0 / 3.0, contentMode: .fit).frame(width: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1)) }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(collection.name).font(.system(size: 56, weight: .bold)).lineLimit(2)
                        Text(collection.count).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        if let overview = collection.info.overview, !overview.isEmpty {
                            Text(overview).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8)).lineSpacing(5).lineLimit(5)
                                .frame(maxWidth: 1100, alignment: .leading)
                        }
                    }.padding(.bottom, 8)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 36)], alignment: .leading, spacing: 36) {
                    ForEach(collection.titles) { title in
                        VStack(alignment: .leading, spacing: 4) {
                            FilmCard(item: libraryItem(title), api: api, config: config)
                            Text(LibraryCollection.line(title)).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).focusSection()
            }
            .padding(.horizontal, TVLayout.edge).padding(.top, 158 + ScreenLayout.top).padding(.bottom, 70)
        }
        .background(alignment: .top) {
            if let backdrop = collection.info.backdrop {
                ArtworkView(url: backdrop, background: true, fill: true).frame(height: 760)
                    .mask(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .horizontal)
    }
}
