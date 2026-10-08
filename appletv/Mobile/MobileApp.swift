import SwiftUI

extension Color {
    static let torrentAccent = Color(red: 0.23, green: 0.576, blue: 1)
}

@main
struct TorrentTubeMobileApp: App {
    @State private var store = AppStore()
    @State private var history = ResumeHistory()
    @State private var favorites = FavoritesStore()
    @State private var localizer = Localizer.shared
    @State private var reconnected = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let api = store.api, let config = store.config {
                    MobileRoot(store: store, api: api, config: config)
                        .id(api.baseURL)
                } else {
                    MobileConnection(store: store)
                }
            }
            .environment(history).environment(favorites)
            .environment(\.locale, localizer.language.locale)
            .preferredColorScheme(.dark).tint(.torrentAccent)
            .task {
                guard !reconnected else { return }
                reconnected = true
                if !store.address.isEmpty { await store.connect() }
            }
        }
    }
}

struct MobileConnection: View {
    @Bindable var store: AppStore
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "play.square.fill").font(.system(size: 56)).foregroundStyle(Color.torrentAccent)
                        Text("Torrent Tube").font(.largeTitle.bold())
                        Text(L("Connect to your server")).font(.title3).foregroundStyle(.secondary)
                    }.padding(.vertical, 20)
                }.listRowBackground(Color.clear)
                Section(L("Server address")) {
                    TextField("http://192.168.0.102:5058", text: $store.address)
                        .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("server-address")
                        .onSubmit { Task { await store.connect() } }
                    Button { Task { await store.connect() } } label: {
                        HStack { Text(L("Connect")); Spacer(); if store.connecting { ProgressView() } }
                    }.disabled(store.connecting || store.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("connect")
                }
                if let error = store.error {
                    Section {
                        Text(error).foregroundStyle(.orange)
                        Text(L("Use the same Wi-Fi as your server. Allow Local Network access in Settings."))
                        Button(L("Open device settings")) { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                }
            }.navigationTitle(L("Welcome")).navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MobileRoot: View {
    let store: AppStore
    let api: TorrentTubeAPI
    let config: ServerConfig
    @State private var catalog = CatalogStore()
    @State private var context: MobileContext
    @State private var settings = false
    @State private var tab = "home"
    @Environment(\.horizontalSizeClass) private var sizeClass
    init(store: AppStore, api: TorrentTubeAPI, config: ServerConfig) {
        self.store = store; self.api = api; self.config = config
        _context = State(initialValue: MobileContext(api: api, config: config))
    }
    // Each tab's own stack; tapping the current tab again (or leaving it) returns to its top.
    @State private var paths: [String: NavigationPath] = [:]
    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            if new == tab { paths[tab] = NavigationPath() }
            tab = new
        })) {
            // Outlined icons, the same as the Apple TV tab bar (tab bars fill them by default).
            Tab(value: "home") {
                destination("home", title: nil) { MobileHome(api: api, config: config) }
            } label: { TabIcon(title: "Home", symbol: "house") }
            // The same tabs, in the same order, as on Apple TV.
            if config.searchEnabled {
                Tab(value: "movies") {
                    destination("movies", title: "Movies") {
                        MobileCategory(options: [("movies", "All"), ("docs", "Documentaries"), ("ukrainian", "Ukrainian")], api: api, config: config)
                    }
                } label: { TabIcon(title: "Movies", symbol: "film") }
                Tab(value: "tv") {
                    destination("tv", title: "TV Shows") { MobileCategory(options: [("tv", "TV Shows")], api: api, config: config) }
                } label: { TabIcon(title: "TV Shows", symbol: "tv") }
                Tab(value: "cartoons") {
                    destination("cartoons", title: "Cartoons") { MobileCategory(options: [("cartoons", "Cartoons")], api: api, config: config) }
                } label: { TabIcon(title: "Cartoons", symbol: "face.smiling.fill") }  // in current SF Symbols the ".fill" face is the outlined one
            }
            Tab(value: "library") {
                destination("library", title: "Library") { MobileLibrary(api: api) }
            } label: { TabIcon(title: "Library", symbol: "folder") }
            // iPad has room for Search in the bar; on iPhone it would push a sixth tab
            // under "More", so there it is the magnifier next to Settings.
            if sizeClass == .regular {
                Tab(value: "search", role: .search) {
                    destination("search", title: "Search") { MobileSearch(api: api, config: config) }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.mobileEdge, sizeClass == .regular ? 32 : 16)
        .environment(catalog)
        .environment(context)
        .sheet(isPresented: $settings) { MobileSettings(store: store, api: api, config: config).environment(catalog) }
    }
    private func destination<Content: View>(_ key: String, title: String?, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { paths[key] ?? NavigationPath() }, set: { paths[key] = $0 })) {
            content()
                .firmTopEdge(title != nil)  // plain lists get a solid bar; the hero screens keep the soft fade
                .navigationTitle(title.map { L($0) } ?? "")
                .navigationBarTitleDisplayMode(title == nil ? .inline : .large)
                .navigationDestination(for: MediaItem.self) { MobileTitle(item: $0, api: api, config: config) }
                .navigationDestination(for: SearchRoute.self) { _ in
                    MobileSearch(api: api, config: config).navigationTitle(L("Search"))
                }
                // Settings on the left, Search on the right - both white, not the accent blue.
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { settings = true } label: { Label(L("Settings"), systemImage: "gearshape") }
                            .tint(.white).accessibilityIdentifier("settings")
                    }
                    if sizeClass != .regular && key != "search" {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { paths[key, default: NavigationPath()].append(SearchRoute()) } label: { Label(L("Search"), systemImage: "magnifyingglass") }
                                .tint(.white).accessibilityIdentifier("open-search")
                        }
                    }
                }
        }
    }
}

struct MobileSettings: View {
    let store: AppStore
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    @Environment(ResumeHistory.self) private var history
    @State private var localizer = Localizer.shared
    @AppStorage("showContinueWatching") private var showContinue = true
    @AppStorage("seekInterval") private var seekInterval = 10
    @AppStorage("recentSearches") private var recent = ""
    @AppStorage("libraryMetadata") private var libraryMetadata = true
    @State private var refreshingMetadata = false
    @State private var cacheSummary = ""
    @State private var clearHistory = false
    @State private var refreshing = false
    private func updateCacheSummary() {
        let cache = catalog.metadataCache(api.baseURL)
        cacheSummary = L("Saved on this device: %ld titles · %@", cache.matchedCount,
                         ByteCountFormatter.string(fromByteCount: Int64(cache.bytes), countStyle: .file))
    }
    private func header(_ title: String, _ icon: String) -> some View {
        // A fixed icon column, so every section title starts on the same line.
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 24)
            Text(L(title))
        }.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).textCase(nil)
    }
    var body: some View {
        NavigationStack {
            // The same sections, in the same order and with the same icons, as Settings on Apple TV.
            Form {
                Section {
                    Toggle(L("Continue Watching"), isOn: $showContinue).tint(Color.torrentAccent)
                } header: { header("Home", "rectangle.topthird.inset.filled") } footer: {
                    Text(L("Display your unfinished titles on Home. Saved positions are kept."))
                }
                Section {
                    Picker(L("Skip forward and back"), selection: $seekInterval) {
                        ForEach([10, 15, 30], id: \.self) { Text(L("%ld seconds", $0)).tag($0) }
                    }.pickerStyle(.menu)
                    NavigationLink(L("Player licenses")) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L("Playback uses VideoLAN’s VLCKit library. Source: %@", "https://code.videolan.org/videolan/VLCKit"))
                                Text(Bundle.main.url(forResource: "VLCKit-COPYING", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? L("License file unavailable.")).font(.caption)
                            }.padding()
                        }.navigationTitle(L("Player licenses"))
                    }
                } header: { header("Playback", "play.circle") } footer: {
                    Text(L("Audio and subtitles can be changed while a title is playing. Available tracks depend on the video file."))
                }
                Section {
                    Picker(L("App language"), selection: $localizer.language) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                    }.pickerStyle(.menu)
                } header: { header("Language", "globe") } footer: {
                    Text(L("Menus, buttons and messages. Titles and descriptions come from your server’s catalog settings."))
                }
                Section {
                    Toggle(L("Posters and details"), isOn: $libraryMetadata).tint(Color.torrentAccent)
                    Button {
                        Task {
                            refreshingMetadata = true
                            await catalog.refreshMetadata(api: api)
                            await catalog.loadLibrary(api: api)
                            await catalog.enrich(catalog.library.map(libraryItem), api: api, config: config)
                            updateCacheSummary()
                            refreshingMetadata = false
                        }
                    } label: { HStack { Text(L("Refresh library metadata")); Spacer(); if refreshingMetadata { ProgressView() } } }
                        .disabled(refreshingMetadata)
                } header: { header("Library", "folder") } footer: {
                    Text(L("Look up library titles on TMDB. Matches are saved on this device, so the Library opens without waiting.") + "\n" + cacheSummary)
                        .onAppear { updateCacheSummary() }
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Server address")).font(.caption).foregroundStyle(.secondary)
                        Text(api.baseURL.absoluteString).textSelection(.enabled)
                    }
                    Button(L("Change server")) { dismiss(); store.disconnect() }
                    Button {
                        Task {
                            refreshing = true
                            catalog.metadata = [:]; catalog.details = [:]
                            for feed in Array(catalog.rows.keys) { await catalog.loadFeed(feed, api: api, config: config, refresh: true) }
                            await catalog.loadLibrary(api: api)
                            refreshing = false
                        }
                    } label: { HStack { Text(L("Refresh catalog")); Spacer(); if refreshing { ProgressView() } } }
                        .disabled(refreshing)
                    Button(L("Clear viewing history"), role: .destructive) { clearHistory = true }
                    Button(L("Clear recent searches"), role: .destructive) { recent = "" }.disabled(recent.isEmpty)
                } header: { header("Server & Storage", "externaldrive") } footer: { Text(L("Favorites and viewing history stay on this device.")) }
                Section {
                    LabeledContent("Torrent Tube", value: L("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"))
                } header: { header("About", "info.circle") }
            }
            // White controls like the rest of the app; the accent stays on the switch.
            .tint(.white)
            .navigationTitle(L("Settings"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() }.tint(.white) } }
                .confirmationDialog(L("Clear viewing history?"), isPresented: $clearHistory, titleVisibility: .visible) {
                    Button(L("Clear viewing history"), role: .destructive) { history.clear(server: api.baseURL) }
                }
        }
    }
}

extension View {
    /// iOS 26: content scrolls under a solid bar instead of a soft fade.
    @ViewBuilder func firmTopEdge(_ enabled: Bool) -> some View {
        if #available(iOS 26.0, *), enabled { scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }
}

/// Search pushed onto the current tab's stack (iPhone).
struct SearchRoute: Hashable {}

/// A tab's title with its outlined icon - matching the Apple TV tab bar.
struct TabIcon: View {
    let title: String
    let symbol: String
    var body: some View {
        Label { Text(L(title)) } icon: {
            Image(systemName: symbol).renderingMode(.template).symbolRenderingMode(.monochrome)
        }
        .environment(\.symbolVariants, .none)
    }
}
