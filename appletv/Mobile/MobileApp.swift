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
    /// At launch with a saved server: the splash, until the first try ends.
    @State private var launching = !(UserDefaults.standard.string(forKey: "serverAddress") ?? "").isEmpty
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
                } else if launching {
                    SplashView()
                } else {
                    MobileConnection(store: store)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: launching)
            .environment(history).environment(favorites)
            .environment(\.locale, localizer.language.locale)
            .preferredColorScheme(.dark).tint(.torrentAccent)
            .task {
                guard !reconnected else { return }
                reconnected = true
                if !store.address.isEmpty {
                    let started = Date()
                    await store.connect()
                    // A short, calm splash rather than a flash.
                    let shown = Date().timeIntervalSince(started)
                    if store.api != nil, shown < 0.8 { try? await Task.sleep(for: .seconds(0.8 - shown)) }
                }
                launching = false
            }
            #if os(macOS)
            .background(BarelessWindow())
            .frame(minWidth: 1120, minHeight: 680)
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        #endif
    }
}

/// The welcome screen: the brand on a glowing backdrop and one glass card
/// with the server address - the same design as on Apple TV.
struct MobileConnection: View {
    @Bindable var store: AppStore
    private enum Field: Hashable { case address, scan, connect }
    @FocusState private var field: Field?
    @State private var scanning = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var canConnect: Bool { !store.connecting && !scanning && !store.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
                            .textFieldStyle(.plain)  // no extra macOS frame inside our own field
                            .foregroundStyle(.white)
                            .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($field, equals: .address)
                            .padding(.horizontal, 14).frame(height: 50)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(field == .address ? Color.torrentAccent : .white.opacity(0.12), lineWidth: field == .address ? 1.5 : 1))
                            .accessibilityIdentifier("server-address")
                            .onSubmit { Task { await store.connect() } }
                        if let error = store.error {
                            ConnectionProblemView(title: error, tip: store.errorTip) { ScreenSleep.openNetworkSettings() }
                        }
                        actionButtons
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

    @ViewBuilder
    private var actionButtons: some View {
        let isWide = sizeClass == .regular || DeviceKind.isLargeScreen
        if isWide {
            HStack(spacing: 12) {
                scanButton
                connectButton
            }
            .padding(.top, 4)
        } else {
            VStack(spacing: 8) {
                scanButton
                connectButton
            }
            .padding(.top, 4)
        }
    }

    private var scanButton: some View {
        Button {
            field = nil
            Task { await scanNetwork() }
        } label: {
            HStack(spacing: 10) {
                if scanning { ProgressView().tint(.white) }
                Text(scanning ? L("Scanning Network…") : L("Scan Network")).font(HeroFont.button)
                if !scanning { Image(systemName: "antenna.radiowaves.left.and.right").font(HeroFont.button) }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .focused($field, equals: .scan)
        .disabled(scanning || store.connecting)
        .accessibilityIdentifier("scan-network")
    }

    private var connectButton: some View {
        Button { field = nil; Task { await store.connect() } } label: {
            HStack(spacing: 10) {
                if store.connecting { ProgressView().tint(.black) }
                Text(store.connecting ? L("Connecting…") : L("Connect")).font(HeroFont.button)
                if !store.connecting { Image(systemName: "arrow.right").font(HeroFont.button) }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.black)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .focused($field, equals: .connect)
        .disabled(!canConnect)
        .opacity(canConnect || store.connecting ? 1 : 0.45)
        .accessibilityIdentifier("connect")
    }

    private func scanNetwork() async {
        scanning = true
        defer { scanning = false }
        if let found = await NetworkScanner.shared.scan(existingAddress: store.address) {
            store.address = found
            field = .connect
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
    @State private var searching = false
    @State private var tab = "home"
    /// Mac: the top row's search field; while it has text the tab shows results.
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    /// Mac: how deep Settings sits in the current tab's stack (nil: not open).
    @State private var settingsDepth: Int?
    @Environment(\.horizontalSizeClass) private var sizeClass
    init(store: AppStore, api: TorrentTubeAPI, config: ServerConfig) {
        self.store = store; self.api = api; self.config = config
        _context = State(initialValue: MobileContext(api: api, config: config))
    }
    // Each tab's own stack; tapping the current tab again (or leaving it) returns to its top.
    @State private var paths: [String: NavigationPath] = [:]
    var body: some View {
        root
            .environment(\.mobileEdge, sizeClass == .regular ? 32 : 16)
            .environment(catalog)
            .environment(context)
            .sheet(isPresented: $settings) {
                MobileSettings(store: store, api: api, config: config)
                    .environment(catalog)
                    .presentationBackground { AppBackground() }
            }
            .fullScreenCover(isPresented: $searching) {
                MobileSearch(api: api, config: config)
                    .environment(catalog)
                    .environment(context)
            }
    }
    private func select(_ new: String) {
        if new == tab { paths[tab] = NavigationPath() }
        tab = new
        searchText = ""
        settingsDepth = nil
    }
    #if os(macOS)
    /// The Mac window has no title bar or toolbar: the tabs, Settings, Search
    /// and Back sit in one row over the page, which also drags the window.
    private var root: some View {
        let tabs: [(key: String, title: String, symbol: String)] = [("home", "Home", "house")]
            + (config.searchEnabled ? [("movies", "Movies", "film"), ("tv", "TV Shows", "tv"), ("cartoons", "Cartoons", "face.smiling.fill")] : [])
            + [("library", "Library", "folder")]
        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let canGoBack = !(paths[tab]?.isEmpty ?? true) || searching
        let inSettings = settingsDepth.map { (paths[tab]?.count ?? 0) >= $0 } ?? false
        return page(tab)
            .id(tab)
            #if DEBUG
            // Screenshots without clicking: -macOpen settings | search
            .task {
                switch UserDefaults.standard.string(forKey: "macOpen") {
                case "settings": open(SettingsRoute()); settingsDepth = paths[tab]?.count
                case "search": searchText = "Friends"
                case "title":
                    for _ in 0..<40 where catalog.library.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                    if let first = catalog.library.first { open(libraryItem(first)) }
                default: break
                }
            }
            #endif
            .toolbar(.hidden, for: .windowToolbar)  // the system Back arrow too: the row below has its own
            .buttonBorderShape(.capsule)  // round buttons, as on iPhone and iPad
            .safeAreaPadding(.top, MacBar.height)
            .overlay(alignment: .top) {
                // Fixed places on every screen: Settings, then Back, on the left
                // (Back dims when there is nowhere to go), the tabs in the
                // exact centre, the search field on the right.
                ZStack {
                    // No bar, only a fade: pages scrolling under the row stay out of its way.
                    LinearGradient(colors: [Color.appBase.opacity(0.85), Color.appBase.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: MacBar.height + 36).frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                    Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
                    HStack(spacing: 2) {
                        ForEach(tabs, id: \.key) { item in
                            let current = tab == item.key && !searching
                            Button { select(item.key) } label: {
                                Label(L(item.title), systemImage: item.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(current ? Color.torrentAccent : .white)
                                    .padding(.horizontal, 16).frame(height: MacBar.control - 8)
                                    .background(current ? Color.white.opacity(0.14) : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                    HStack(spacing: 10) {
                        MacBarButton(symbol: "gearshape", label: L("Settings")) {
                            searchText = ""
                            if !inSettings { open(SettingsRoute()); settingsDepth = paths[tab]?.count }
                        }
                            .keyboardShortcut(",", modifiers: .command)
                        MacBarButton(symbol: "chevron.left", label: L("Back")) { goBack() }
                            .disabled(!canGoBack).opacity(canGoBack ? 1 : 0.35)
                            .keyboardShortcut("[", modifiers: .command)
                        Spacer(minLength: 0)
                        // Settings needs no search; the slot stays so nothing moves.
                        MacSearchField(text: $searchText, focused: $searchFocused)
                            .opacity(inSettings ? 0 : 1).allowsHitTesting(!inSettings)
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: MacBar.height)
                // Pinned to the window's top edge: pushed pages (a title,
                // Settings) get a taller top inset, and the row must not follow it.
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
            .onChange(of: paths[tab]?.count ?? 0) { _, count in
                if let depth = settingsDepth, count < depth { settingsDepth = nil }
            }
            .onChange(of: searching) { _, now in if now { paths[tab] = NavigationPath() } }
    }
    private func goBack() {
        if var path = paths[tab], !path.isEmpty { path.removeLast(); paths[tab] = path }
        else { searchText = ""; searchFocused = false }
    }
    /// Settings and Search open in the window, over the current tab.
    private func open<Route: Hashable>(_ route: Route) {
        var path = paths[tab] ?? NavigationPath()
        path.append(route)
        paths[tab] = path
    }
    @ViewBuilder private func page(_ key: String) -> some View {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            destination(key, title: nil) { MobileSearch(api: api, config: config, sharedQuery: $searchText) }
        } else {
            tabPage(key)
        }
    }
    @ViewBuilder private func tabPage(_ key: String) -> some View {
        switch key {
        case "movies":
            destination("movies", title: "Movies") {
                MobileCategory(options: [("movies", "All"), ("docs", "Documentaries"), ("ukrainian", "Ukrainian")], api: api, config: config)
            }
        case "tv": destination("tv", title: "TV Shows") { MobileCategory(options: [("tv", "TV Shows")], api: api, config: config) }
        case "cartoons": destination("cartoons", title: "Cartoons") { MobileCategory(options: [("cartoons", "Cartoons")], api: api, config: config) }
        case "library": destination("library", title: "Library") { MobileLibrary(api: api) }
        default: destination("home", title: nil) { MobileHome(api: api, config: config) }
        }
    }
    #else
    private var root: some View {
        TabView(selection: Binding(get: { tab }, set: { select($0) })) {
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
            // iPad and iPhone both keep Search on the right side of the top bar;
            // it is not placed as an icon item in the main menu tab bar.
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    #endif
    private func destination<Content: View>(_ key: String, title: String?, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { paths[key] ?? NavigationPath() }, set: { paths[key] = $0 })) {
            content()
                .background(AppBackground())
                .softTopEdge()
                .navigationTitle(title.map { L($0) } ?? "")
                .navigationBarTitleDisplayMode(title == nil ? .inline : .large)
                .navigationDestination(for: MediaItem.self) { MobileTitle(item: $0, api: api, config: config) }
                #if os(macOS)
                .navigationDestination(for: SettingsRoute.self) { _ in MobileSettings(store: store, api: api, config: config) }
                #endif
                // Settings on the left, Search on the right - both white, not the accent blue.
                // (The Mac has them in its own top row.)
                #if !os(macOS)
                .toolbar {
                    ToolbarItem(placement: .leadingBar) {
                        Button { settings = true } label: { Label(L("Settings"), systemImage: "gearshape") }
                            .tint(.white).accessibilityIdentifier("settings")
                    }
                    ToolbarItem(placement: .trailingBar) {
                        Button { searching = true } label: {
                            Label(L("Search"), systemImage: "magnifyingglass")
                        }
                        .tint(.white)
                        .accessibilityIdentifier("open-search")
                    }
                }
                #endif
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
    @AppStorage("previewFocusedTitle") private var previewTitle = true
    @AppStorage("seekInterval") private var seekInterval = 10
    @AppStorage("recentSearches") private var recent = ""
    @AppStorage("libraryMetadata") private var libraryMetadata = true
    @State private var refreshingMetadata = false
    @State private var clearHistory = false
    @State private var refreshing = false
    @State private var refreshMessage: String?
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "VLCKit-COPYING", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L("License file unavailable.")
        }
        return text
    }
    private var libraryFooterText: String {
        let intro = L("Look up library titles on TMDB. Matches are saved on this device, so the Library opens without waiting.")
        let summary = catalog.syncSummary(api.baseURL)
        return "\(intro)\n\(summary)"
    }
    private func header(_ title: String, _ icon: String) -> some View {
        // A fixed icon column, so every section title starts on the same line.
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 24)
            Text(L(title))
        }.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).textCase(nil)
    }
    @ViewBuilder private var homeSection: some View {
        Section {
            Toggle(L("Continue Watching"), isOn: $showContinue).tint(Color.torrentAccent)
            Toggle(L("Title preview while browsing"), isOn: $previewTitle).tint(Color.torrentAccent)
        } header: { header("Home", "rectangle.topthird.inset.filled") } footer: {
            Text(L("Display your unfinished titles on Home. Title preview updates the banner as you move between titles."))
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    @ViewBuilder private var playbackSection: some View {
        Section {
            Picker(L("Skip"), selection: $seekInterval) {
                ForEach([10, 15, 30], id: \.self) { Text(L("%ld seconds", $0)).tag($0) }
            }.pickerStyle(.menu)
            NavigationLink(L("Player licenses")) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Playback uses VideoLAN’s VLCKit library. Source: %@", "https://code.videolan.org/videolan/VLCKit"))
                        Text(licenseText).font(.caption)
                    }.padding()
                }.navigationTitle(L("Player licenses"))
            }
        } header: { header("Playback", "play.circle") } footer: {
            Text(L("Choose how far the player moves with each skip. Audio and subtitles can be changed while a title is playing."))
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    @ViewBuilder private var languageSection: some View {
        Section {
            Picker(L("App language"), selection: $localizer.language) {
                ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.menu)
        } header: { header("Language", "globe") } footer: {
            Text(L("Menus, buttons and messages. Titles and descriptions come from your server’s catalog settings."))
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    @ViewBuilder private var librarySection: some View {
        Section {
            Toggle(L("Posters and details"), isOn: $libraryMetadata).tint(Color.torrentAccent)
            Button {
                Task { await catalog.syncNow(api: api, config: config, rescan: false) }
            } label: { HStack { Text(L("Sync now")).foregroundStyle(.white); Spacer(); if catalog.syncing && !refreshingMetadata { ProgressView() } } }
                .disabled(catalog.syncing)
            Button {
                Task {
                    refreshingMetadata = true
                    await catalog.syncNow(api: api, config: config, rescan: true)
                    refreshingMetadata = false
                }
            } label: { HStack { Text(L("Rescan library")).foregroundStyle(.white); Spacer(); if refreshingMetadata { ProgressView() } } }
                .disabled(refreshingMetadata || catalog.syncing)
        } header: { header("Library", "folder") } footer: {
            Text(libraryFooterText).font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    @ViewBuilder private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Server address")).font(.caption).foregroundStyle(.secondary)
                Text(api.baseURL.absoluteString).textSelection(.enabled)
            }
            if !config.supportsPlayback {
                Label(L("Update your server to enable streaming on this device."), systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Button(L("Change server")) { dismiss(); store.disconnect() }.foregroundStyle(.white)
            Button {
                Task {
                    refreshing = true
                    refreshMessage = nil
                    await catalog.loadFeed("new", api: api, config: config, refresh: true)
                    await catalog.loadLibrary(api: api)
                    for feed in ["popular", "movies", "tv", "cartoons", "ukrainian"] {
                        await catalog.loadFeed(feed, api: api, config: config, refresh: true)
                    }
                    refreshMessage = catalog.errors.values.first ?? catalog.libraryError ?? L("Catalog updated.")
                    refreshing = false
                }
            } label: {
                HStack {
                    Text(L("Refresh catalog")).foregroundStyle(.white)
                    Spacer()
                    if refreshing { ProgressView() }
                    else if let refreshMessage { Text(refreshMessage).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .disabled(refreshing)
            Button(L("Clear viewing history"), role: .destructive) { clearHistory = true }
            Button(L("Clear recent searches"), role: .destructive) { recent = "" }.disabled(recent.isEmpty)
        } header: { header("Server & Storage", "externaldrive") } footer: {
            Text(L("Favorites and viewing history stay on this device.")).font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    @ViewBuilder private var aboutSection: some View {
        Section {
            LabeledContent("Torrent Tube", value: L("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"))
        } header: { header("About", "info.circle") }
        .listRowBackground(Color.white.opacity(0.06))
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    /// On the Mac, Settings is a page of the current tab; elsewhere a sheet.
    @ViewBuilder private func settingsStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        content()
        #else
        NavigationStack { content() }
        #endif
    }

    var body: some View {
        settingsStack {
            Form {
                homeSection
                playbackSection
                languageSection
                librarySection
                serverSection
                aboutSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            .buttonStyle(.plain)  // action rows read as list rows, not grey push buttons
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
            #endif
            // White controls like the rest of the app; the accent stays on the switch.
            .tint(.white)
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(L("Settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() }.tint(.white).accessibilityIdentifier("done-settings") } }
            .confirmationDialog(L("Clear viewing history?"), isPresented: $clearHistory, titleVisibility: .visible) {
                Button(L("Clear viewing history"), role: .destructive) { history.clear(server: api.baseURL) }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("Saved playback positions for this server will be removed from this device. Your server files stay untouched."))
            }
        }
        .presentationBackground { AppBackground() }
    }
}

extension View {
    /// Blend scrolling content into the navigation controls, as on Home.
    @ViewBuilder func softTopEdge() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }
}

/// Search pushed onto the current tab's stack (iPhone).
struct SearchRoute: Hashable {}
/// Settings pushed onto the current tab's stack (Mac).
struct SettingsRoute: Hashable {}

/// A tab's title with its outlined icon - matching the Apple TV tab bar.
struct TabIcon: View {
    let title: String
    let symbol: String
    var body: some View {
        Label { Text(L(title)) } icon: {
            Image(systemName: symbol)
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .symbolEffectsRemoved()  // no bounce when a tab is tapped
        }
        .environment(\.symbolVariants, .none)
    }
}
