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
    init() {
        // Posters, backdrops and cast photos stay on the device between launches.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 1 << 30)
    }

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

/// The welcome screen: the brand on a glowing backdrop and one glass card
/// with the server address - the same design as on Apple TV.
struct MobileConnection: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var canConnect: Bool { !store.connecting && !store.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        ZStack {
            BrandBackground()
            GeometryReader { screen in
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        BrandMark(size: sizeClass == .regular ? 104 : 88)
                        Text("Torrent Tube").font(.system(size: sizeClass == .regular ? 44 : 36, weight: .heavy))
                        Text(L("Enter the address of your Torrent Tube server."))
                            .font(.callout).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(L("Server address"), systemImage: "server.rack")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        TextField("", text: $store.address, prompt: Text(verbatim: "http://192.168.0.102:5058").foregroundStyle(.white.opacity(0.3)))
                            .foregroundStyle(.white)
                            .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focused)
                            .padding(.horizontal, 14).frame(height: 50)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(focused ? Color.torrentAccent : .white.opacity(0.12), lineWidth: focused ? 1.5 : 1))
                            .accessibilityIdentifier("server-address")
                            .onSubmit { Task { await store.connect() } }
                        Text(L("Example: %@", "http://192.168.0.102:5058")).font(.caption).foregroundStyle(.white.opacity(0.45))
                        if let error = store.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text(L("Use the same Wi-Fi as your server. Allow Local Network access in Settings."))
                                    .foregroundStyle(.white.opacity(0.6))
                                Button(L("Open device settings")) { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                                    .font(.footnote.weight(.semibold))
                            }
                            .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        }
                        Button { focused = false; Task { await store.connect() } } label: {
                            HStack(spacing: 10) {
                                if store.connecting { ProgressView().tint(.black) }
                                Text(store.connecting ? L("Connecting…") : L("Connect")).font(.headline)
                                if !store.connecting { Image(systemName: "arrow.right").font(.headline) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.black)
                            .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canConnect)
                        .opacity(canConnect || store.connecting ? 1 : 0.45)
                        .accessibilityIdentifier("connect")
                        .padding(.top, 6)
                    }
                    .padding(22)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                    Label(L("The server and this device must be on the same network."), systemImage: "wifi")
                        .font(.footnote).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20).padding(.vertical, 32)
                .frame(maxWidth: 520)
                // Centred on the screen like on Apple TV; it scrolls when the keyboard needs room.
                .frame(maxWidth: .infinity, minHeight: screen.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            }
        }
        .tint(Color.torrentAccent)
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
    @State private var clearHistory = false
    @State private var refreshing = false
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
                    Picker(L("Skip"), selection: $seekInterval) {
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
                        Task { await catalog.syncNow(api: api, config: config, rescan: false) }
                    } label: { HStack { Text(L("Sync now")); Spacer(); if catalog.syncing && !refreshingMetadata { ProgressView() } } }
                        .disabled(catalog.syncing)
                    Button {
                        Task {
                            refreshingMetadata = true
                            await catalog.syncNow(api: api, config: config, rescan: true)
                            refreshingMetadata = false
                        }
                    } label: { HStack { Text(L("Rescan library")); Spacer(); if refreshingMetadata { ProgressView() } } }
                        .disabled(refreshingMetadata || catalog.syncing)
                } header: { header("Library", "folder") } footer: {
                    Text(L("Look up library titles on TMDB. Matches are saved on this device, so the Library opens without waiting.") + "\n" + catalog.syncSummary(api.baseURL))
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
