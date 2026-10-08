import SwiftUI
import TVServices

struct SettingsView: View {
    let store: AppStore
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(ResumeHistory.self) private var history
    @AppStorage("showNewInTopShelf", store: TopShelfStore.defaults) private var showNew = false
    @AppStorage("showContinueWatching") private var showContinue = true
    @AppStorage("previewFocusedTitle") private var previewTitle = true
    @AppStorage("seekInterval") private var seekInterval = 10
    @AppStorage("recentSearches") private var recentSearches = ""
    @AppStorage("libraryMetadata") private var libraryMetadata = true
    @State private var refreshingMetadata = false
    @State private var section: Section = .home
    @State private var localizer = Localizer.shared
    @FocusState private var focusedSection: Section?
    @State private var clearingHistory = false
    @State private var refreshing = false
    @State private var refreshMessage: String?
    private enum Section: String, CaseIterable {
        case home = "Home & Top Shelf", playback = "Playback", language = "Language", library = "Library", server = "Server & Storage"
        var icon: String {
            switch self { case .language: "globe"; case .home: "rectangle.topthird.inset.filled"; case .playback: "play.circle"; case .library: "folder"; case .server: "externaldrive" }
        }
    }
    var body: some View {
        // The title spans both columns, so the section list and the
        // settings start on the same line and their rows share one grid.
        VStack(alignment: .leading, spacing: 32) {
        Text(L("Settings")).accessibilityIdentifier("settings-heading").font(.system(size: 54, weight: .bold)).padding(.horizontal, 14)
        HStack(alignment: .top, spacing: 68) {
            VStack(alignment: .leading, spacing: 38) {
                VStack(spacing: 16) {
                    ForEach(Section.allCases, id: \.self) { value in
                        Button { section = value } label: {
                            HStack(spacing: 20) {
                                Image(systemName: value.icon).font(.system(size: 26, weight: .medium)).frame(width: 36)
                                Text(L(value.rawValue)).font(.system(size: 28, weight: .semibold))
                                Spacer(minLength: 0)
                                if section == value { Image(systemName: "chevron.right").font(.system(size: 20, weight: .semibold)) }
                            }
                        }.buttonStyle(TVSelectionRowStyle()).focused($focusedSection, equals: value)
                    }
                }.focusSection()
                Text("Torrent Tube\n" + L("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineSpacing(6).padding(.horizontal, 28)
            }.frame(width: 460, alignment: .leading).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .language:
                        ForEach(AppLanguage.allCases) { language in
                            Button { localizer.language = language } label: {
                                HStack {
                                    Text(language.name).font(.system(size: 34, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).opacity(localizer.language == language ? 1 : 0)
                                }
                            }
                            .buttonStyle(TVSelectionRowStyle())
                            .accessibilityAddTraits(localizer.language == language ? .isSelected : [])
                            .accessibilityIdentifier("language-\(language.rawValue)")
                        }
                        Text(L("Menus, buttons and messages. Titles and descriptions come from your server’s catalog settings."))
                            .font(.system(size: 25)).foregroundStyle(.white.opacity(0.7)).lineSpacing(4).padding(.horizontal, 34).padding(.top, 10)
                    case .home:
                        setting("Top Shelf", value: showNew ? L("New titles") : L("Brand artwork"), subtitle: "Shown above the app on your Apple TV Home screen.") {
                            showNew.toggle()
                            TVTopShelfContentProvider.topShelfContentDidChange()
                            if showNew { Task { await catalog.loadFeed("new", api: api, config: config, refresh: true) } }
                        }
                        Text(config.searchEnabled ? L("New titles update when you open the app or refresh the catalog. If no artwork is available, the brand banner is shown.") : L("New titles need a server with catalog search enabled. The brand banner is shown until then."))
                            .font(.system(size: 25)).foregroundStyle(.white.opacity(0.7)).lineSpacing(4).padding(.horizontal, 34).padding(.vertical, 8)
                        setting("Continue Watching", value: showContinue ? L("Show") : L("Hide"), subtitle: "Display your unfinished titles on Home.") { showContinue.toggle() }
                        setting("Title preview while browsing", value: previewTitle ? L("On") : L("Off"), subtitle: "Update the Home banner as you browse titles.") { previewTitle.toggle() }
                    case .playback:
                        setting("Skip", value: L("%ld seconds", seekInterval), subtitle: "Choose how far the player moves with each skip.") {
                            let intervals = [10, 15, 30]
                            seekInterval = intervals[((intervals.firstIndex(of: seekInterval) ?? 0) + 1) % intervals.count]
                        }
                        Text(L("Audio and subtitles can be changed while a title is playing. Available tracks depend on the video file."))
                            .font(.system(size: 25)).foregroundStyle(.white.opacity(0.7)).lineSpacing(4).padding(.horizontal, 34).padding(.top, 8)
                        NavigationLink { LicenseView() } label: {
                            HStack {
                                Text(L("Player licenses")).font(.system(size: 34, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 22, weight: .semibold)).opacity(0.7)
                            }
                        }.buttonStyle(TVSelectionRowStyle())
                    case .library:
                        setting("Posters and details", value: libraryMetadata ? L("On") : L("Off"),
                                subtitle: "Look up library titles on TMDB and save them on this device.") {
                            libraryMetadata.toggle()
                        }
                        setting("Sync now", value: catalog.syncing && !refreshingMetadata ? L("Syncing…") : nil,
                                subtitle: "Save details and images for new titles on the server.") {
                            Task { await catalog.syncNow(api: api, config: config, rescan: false) }
                        }.disabled(catalog.syncing)
                        setting("Rescan library", value: refreshingMetadata ? L("Refreshing…") : nil,
                                subtitle: "Match all titles again on the server and update details.") {
                            Task {
                                refreshingMetadata = true
                                await catalog.syncNow(api: api, config: config, rescan: true)
                                refreshingMetadata = false
                            }
                        }.disabled(refreshingMetadata || catalog.syncing)
                        Text(catalog.syncSummary(api.baseURL)).font(.system(size: 25)).foregroundStyle(.white.opacity(0.7)).lineSpacing(4)
                            .padding(.horizontal, 34).padding(.top, 10)
                    case .server:
                        Text(api.baseURL.absoluteString).font(.system(size: 28, weight: .medium)).foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 14).padding(.bottom, 8)
                        if !config.supportsPlayback { UpdateServerNotice().padding(.horizontal, 14).padding(.bottom, 8) }
                        setting("Change server", value: nil, subtitle: "Connect to a different Torrent Tube server.") { store.disconnect() }
                        setting("Refresh catalog", value: refreshing ? L("Refreshing…") : nil, subtitle: "Reload Home titles and update Top Shelf.") {
                            Task {
                                refreshing = true
                                await catalog.loadFeed("new", api: api, config: config, refresh: true)
                                await catalog.loadLibrary(api: api)
                                for feed in ["popular", "movies", "tv", "cartoons", "ukrainian"] {
                                    await catalog.loadFeed(feed, api: api, config: config, refresh: true)
                                }
                                refreshMessage = catalog.errors.values.first ?? catalog.libraryError ?? L("Catalog updated.")
                                refreshing = false
                            }
                        }.disabled(refreshing)
                        if let refreshMessage {
                            Text(refreshMessage).font(.system(size: 25, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 34).padding(.top, 8)
                        }
                        setting("Clear viewing history", value: nil, subtitle: "Remove saved positions for this server on this Apple TV.") { clearingHistory = true }
                        setting("Clear recent searches", value: recentSearches.isEmpty ? L("None") : nil, subtitle: "Forget the terms shown on the Search screen.") { recentSearches = "" }
                    }
                }.padding(12)
            }.frame(maxWidth: .infinity).focusSection()
        }
        }
        .padding(.horizontal, 58).padding(.top, ScreenLayout.top).padding(.bottom, 40)
        .defaultFocus($focusedSection, .home, priority: .userInitiated)
        .alert(L("Clear viewing history?"), isPresented: $clearingHistory) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Clear history"), role: .destructive) { history.clear(server: api.baseURL) }
        } message: { Text(L("Saved playback positions for this server will be removed from this Apple TV. Your server files stay untouched.")) }
    }
    private func setting(_ title: String, value: String?, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L(title)).font(.system(size: 34, weight: .semibold))
                    Text(L(subtitle)).font(.system(size: 24, weight: .regular)).opacity(0.72)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
                if let value {
                    Text(value).font(.system(size: 28, weight: .medium)).opacity(0.85)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 22, weight: .semibold)).opacity(0.7)
                }
            }
        }.buttonStyle(TVSelectionRowStyle()).accessibilityIdentifier("setting-\(title)")
    }
}
