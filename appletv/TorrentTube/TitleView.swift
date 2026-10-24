import SwiftUI

struct TitleView: View {
    let item: MediaItem
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @State private var versions: [Release] = []
    @State private var versionsLoading = false
    @State private var versionError: String?
    @State private var showVersions = false
    @State private var trailer: Trailer?
    @State private var findingTrailer = false
    @State private var episodePlaybackError: String?
    @State private var trailerError: String?
    @State private var season = 1
    /// Set once: the page appears again when the player closes, and must keep
    /// the season the viewer was in instead of going back to the first.
    @State private var seasonPicked = false
    @State private var launchingEpisode: Int?
    /// Which show and season `episodes` holds.
    @State private var episodesKey: String?
    /// The episode card with focus: given back when the player closes, so the
    /// page stays at the episodes instead of jumping up to Play.
    @FocusState private var focusedEpisode: Int?
    @State private var selectedEpisode: Int?
    @State private var episodes: [Episode] = []
    @State private var episodeLoading = false
    @State private var playback: PlaybackRequest?
    @State private var pendingPlayback: PlaybackRequest?
    @State private var showServerNotice = false
    @State private var fixingMatch = false
    private var value: MediaItem { catalog.resolved(item) }
    private var details: Details? { catalog.details(for: value) }
    private func playTrailer() {
        findingTrailer = true
        Task {
            defer { findingTrailer = false }
            do {
                if let found = try await TrailerChoice.find(title: item.title, year: details?.year, known: details?.trailers ?? [], api: api) {
                    trailer = found
                } else {
                    trailerError = L("No trailer was found for this title.")
                }
            } catch { trailerError = error.localizedDescription }
        }
    }
    /// Information: what isn't already in the hero's facts line.
    private var infoRows: [(String, String)] {
        guard let details else { return [] }
        var rows: [(String, String)] = []
        if let genres = details.genres, !genres.isEmpty { rows.append((L("Genres"), genres.joined(separator: ", "))) }
        for fact in details.facts ?? [] where !fact.names.isEmpty { rows.append((L(fact.label), fact.names.joined(separator: ", "))) }
        if let countries = details.countries, !countries.isEmpty { rows.append((L("Country"), countries.prefix(3).joined(separator: ", "))) }
        if let certification = details.certification, !certification.isEmpty { rows.append((L("Age rating"), certification)) }
        if let original = details.originalTitle, !original.isEmpty, original != details.title { rows.append((L("Original title"), original)) }
        return rows
    }
    private func recommendationItem(_ rec: Details.Recommendation) -> MediaItem {
        var item = MediaItem(title: rec.title, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
        item.cleanTitle = rec.title; item.poster = rec.poster; item.tmdbId = rec.tmdbId; item.mediaType = rec.mediaType
        return item
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 38) {
                CinemaHero(item: value, details: details, height: 960, overviewLines: nil) {
                    HStack(spacing: 28) {
                        Button { play() } label: { Label(L("Play"), systemImage: "play.fill") }
                            .buttonStyle(WatchButtonStyle()).accessibilityIdentifier("title-play")
                        Button { playTrailer() } label: { Label(findingTrailer ? L("Finding trailer…") : L("Trailer"), systemImage: "play.rectangle") }
                            .disabled(findingTrailer)
                            .buttonStyle(.bordered).tint(.white).accessibilityIdentifier("show-trailers")
                        if item.sourceOverride == nil || (item.releases?.count ?? 0) > 1 {  // a library title saved twice has versions too
                            Button { selectedEpisode = nil; showVersions = true } label: {
                                Image(systemName: "list.bullet")
                            }
                            .buttonStyle(.bordered).tint(.white)
                            .accessibilityLabel(L("Choose version"))
                            .accessibilityIdentifier("choose-version")
                        }
                        FavoriteButton(item: value, details: details, server: api.baseURL)
                        // After the heart: search TMDB and pick the right film or show by hand.
                        if item.sourceOverride?.path != nil && config.capabilities?.libraryMatch == true {
                            Button { fixingMatch = true } label: { Image(systemName: "text.magnifyingglass") }
                                .buttonStyle(.bordered).tint(.white)
                                .accessibilityLabel(L("Fix match")).accessibilityIdentifier("fix-match")
                        }
                    }
                }
                if details?.mediaType == "tv", let seasons = details?.seasonList, !seasons.isEmpty {
                    VStack(alignment: .leading, spacing: 28) {
                        // Seasons in one row above the episodes, the chosen one filled -
                        // all of them in view, no menu to open.
                        if seasons.count > 1 {
                            ScrollView(.horizontal) {
                                HStack(spacing: 18) {
                                    ForEach(seasons) { selection in
                                        let current = selection.number == season
                                        Button { season = selection.number; seasonPicked = true } label: {
                                            Text(selection.name.isEmpty ? L("Season %ld", selection.number) : selection.name)
                                        }
                                        .buttonStyle(ChipStyle(selected: current))
                                        .accessibilityAddTraits(current ? .isSelected : [])
                                        .accessibilityIdentifier("season-\(selection.number)")
                                    }
                                }.padding(.horizontal, TVLayout.edge).padding(.vertical, 14)
                            }.scrollIndicators(.hidden).scrollClipDisabled().focusSection()
                        }
                        Text(seasons.count > 1 ? L("Episodes") : L("Episodes") + " · " + (seasons.first.map { $0.name.isEmpty ? L("Season %ld", $0.number) : $0.name } ?? ""))
                            .font(.system(size: 34, weight: .semibold)).padding(.horizontal, TVLayout.edge)
                        if episodeLoading { LoadingState(text: L("Loading episodes…"), minHeight: 260) }
                        if episodes.isEmpty && !episodeLoading {
                            Text(L("Choose a version to see the episodes available to stream.")).foregroundStyle(.secondary).padding(.horizontal, TVLayout.edge)
                        }
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 32) {
                                ForEach(episodes) { episode in
                                    Button {
                                        launchingEpisode = episode.number
                                    } label: {
                                        // The length sits on the picture, so it is in the same place on
                                        // every card; the whole name goes below it.
                                        VStack(alignment: .leading, spacing: 14) {
                                            ArtworkView(url: episode.still, seed: "\(value.displayTitle) \(episode.number)").frame(width: 380, height: 215)
                                                .overlay(alignment: .bottomTrailing) {
                                                    if let runtime = episode.runtime {
                                                        Text(L("%ld min", runtime)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                                                            .foregroundStyle(.white)
                                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                                            .background(.black.opacity(0.6), in: Capsule())
                                                            .padding(10)
                                                    }
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            Text("\(episode.number). \(episode.name)").font(.system(size: 25, weight: .semibold))
                                                .fixedSize(horizontal: false, vertical: true)  // the whole name, on as many lines as it needs
                                        }.frame(width: 380, alignment: .topLeading)
                                    }.buttonStyle(CinemaCardStyle())
                                        .focused($focusedEpisode, equals: episode.number)
                                        .overlay { if launchingEpisode == episode.number { ProgressView().tint(.white) } }
                                }
                            }.padding(.horizontal, TVLayout.edge).padding(.top, 18).padding(.bottom, 36)
                        // A focused card grows: let it draw past the row, and leave room
                        // below for a name on two or three lines.
                        }.scrollClipDisabled().focusSection()
                    }
                }
                if let people = details?.people, !people.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ShelfHeader(text: L("Cast & Crew"))
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 30) {
                                ForEach(Array(people.prefix(24).enumerated()), id: \.offset) { _, person in PersonCard(person: person) }
                            }.padding(.horizontal, TVLayout.edge).padding(.vertical, 24)
                        }.scrollIndicators(.hidden).scrollClipDisabled().focusSection()
                    }
                }
                if !infoRows.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        ShelfHeader(text: L("Information"))
                        InfoGrid(rows: infoRows).padding(.horizontal, TVLayout.edge)
                    }
                }
                if let recommendations = details?.recommendations, !recommendations.isEmpty {
                    MediaShelf(title: L("More Like This"), items: recommendations.prefix(20).map(recommendationItem), api: api, config: config)
                }
            }.padding(.bottom, 80)
        }
        // Edge to edge like Home: the hero's image runs under the tab bar
        // and to the sides; the rest keeps its own horizontal padding.
        .tvScrollEdge()  // before ignoresSafeArea, so the fade spans the whole screen
        .ignoresSafeArea(edges: [.top, .horizontal])
        .background(AppBackground())
        .alert(L("Streaming unavailable"), isPresented: $showServerNotice) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(L("Update Torrent Tube on your server to stream on this Apple TV.")) }
        .fullScreenCover(isPresented: $showVersions, onDismiss: {
            if let pendingPlayback { playback = pendingPlayback; self.pendingPlayback = nil }
        }) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Choose version")).font(.system(size: 40, weight: .bold))
                        Text(value.displayTitle).font(.system(size: 27)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 40)
                    Button(L("Back")) { showVersions = false }.buttonStyle(.bordered)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let selectedEpisode { Text(L("Season %ld · Episode %ld", season, selectedEpisode)).foregroundStyle(.secondary) }
                        if versionsLoading { LoadingState(text: L("Finding versions…"), minHeight: 480) }
                        if let versionError { ErrorPanel(message: versionError) { Task { await loadVersions() } } }
                        ForEach(versions) { release in
                            Button {
                                if config.supportsPlayback {
                                    pendingPlayback = request(source: release.source)
                                    showVersions = false
                                    if details?.mediaType == "tv" { ReleaseChoice.remember(release.source, title: release.title, for: details?.tmdbId ?? value.tmdbId) }
                                } else { showServerNotice = true; showVersions = false }
                            } label: {
                                HStack(spacing: 28) {
                                    Image(systemName: "play.circle").font(.system(size: 35))
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(release.title).font(.system(size: 26, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                        Text([release.sizeLabel, release.seeders.map { L("%ld seeders", $0) }].compactMap { $0 }.joined(separator: " · "))
                                            .font(.system(size: 22)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }.buttonStyle(TVSelectionRowStyle())
                        }
                        if versions.isEmpty && !versionsLoading && versionError == nil {
                            Button(L("Use this version")) { pendingPlayback = request(source: item.source); showVersions = false }
                        }
                    }.padding(8)
                }.scrollIndicators(.hidden).task { await loadVersions() }
            }
            .padding(48).frame(width: 1200, height: 780)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 28))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.8)).presentationBackground(.clear)
            .onExitCommand { showVersions = false }
        }
        // Trailer: straight into the English trailer, Ukrainian subtitles.
        .fullScreenCover(item: $trailer) { trailer in TrailerPlayer(trailer: trailer, api: api) }
        .alert(L("Unable to play"), isPresented: Binding(get: { episodePlaybackError != nil }, set: { if !$0 { episodePlaybackError = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(episodePlaybackError ?? "") }
        .alert(L("No trailer"), isPresented: Binding(get: { trailerError != nil }, set: { if !$0 { trailerError = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(trailerError ?? "") }
        .fullScreenCover(item: $playback) { request in PlaybackLauncher(request: request, api: api) }
        .fullScreenCover(isPresented: $fixingMatch) {
            if let path = item.sourceOverride?.path {
                TVMatchEditor(itemID: path, api: api) {
                    Task { await catalog.loadDetails(item, api: api, config: config, refresh: true) }
                }
            }
        }
        // Back from the player: tvOS gave focus to Play, so the page jumped up.
        // Give it to the episode that played as the player starts to close.
        .onChange(of: playback == nil) { _, closed in
            if closed, let episode = selectedEpisode { focusedEpisode = episode }
        }
        .task {
            await catalog.enrich([item], api: api, config: config)
            await catalog.loadDetails(item, api: api, config: config)
            if !seasonPicked, let first = details?.seasonList?.first { season = first.number; seasonPicked = true }
        }
        .task(id: "\(details?.tmdbId ?? 0):\(season)") { await loadEpisodes() }
        .onChange(of: season) { launchingEpisode = nil }
        .task(id: launchingEpisode) {
            guard let number = launchingEpisode else { return }
            selectedEpisode = number
            defer { if !Task.isCancelled { launchingEpisode = nil } }
            guard config.supportsPlayback else { showServerNotice = true; return }
            do {
                let source = try await ReleaseChoice.resolveEpisodeSource(for: item, title: value.displayTitle,
                    original: details?.originalTitle, tmdbID: details?.tmdbId ?? value.tmdbId,
                    season: season, episode: number, api: api)
                try Task.checkCancellation()
                playback = request(source: source)
            } catch is CancellationError {} catch { episodePlaybackError = error.localizedDescription }
        }
    }
    private func play() {
        guard config.supportsPlayback else { showServerNotice = true; return }
        selectedEpisode = nil
        playback = request(source: item.source)
    }
    private func request(source: PlaybackSource) -> PlaybackRequest {
        PlaybackRequest(source: source, title: value.displayTitle, artwork: details?.backdrop ?? value.poster,
                        tmdbID: details?.tmdbId ?? value.tmdbId, season: selectedEpisode == nil ? nil : season, episode: selectedEpisode,
                        seasonSources: item.librarySources)
    }
    private func loadVersions() async {
        if let provided = item.releases, selectedEpisode == nil { versions = provided; return }
        versionsLoading = true; versionError = nil
        defer { versionsLoading = false }
        do {
            versions = try await ReleaseChoice.search(title: value.displayTitle, original: details?.originalTitle,
                                                      season: selectedEpisode == nil ? nil : season, api: api)
        } catch is CancellationError {} catch { versionError = error.localizedDescription }
    }
    private func loadEpisodes() async {
        guard let id = details?.tmdbId, details?.mediaType == "tv" else { return }
        let requestedSeason = season
        // The page appears again when the player closes. Emptying the row then
        // made the page shorter, so it scrolled up and back down: keep it.
        let key = "\(id):\(requestedSeason)"
        guard key != episodesKey || episodes.isEmpty else { return }
        episodeLoading = true; episodes = []
        defer { if requestedSeason == season { episodeLoading = false } }
        if let response: EpisodeResponse = try? await api.request("api/episodes", query: [.init(name: "id", value: String(id)), .init(name: "season", value: String(requestedSeason))]), !Task.isCancelled, requestedSeason == season {
            episodes = response.episodes
            episodesKey = key
        }
    }
}

/// Fix match on Apple TV, laid out like Search: a large query line and the
/// app's own keyboard on the left, with chips for film or show, language and
/// year; on the right the title's files and the results as posters, with
/// room around them so a focused poster is never cut. Searches as you type.
struct TVMatchEditor: View {
    let api: TorrentTubeAPI
    let onSaved: () -> Void
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var editor: MatchEditor
    @State private var choice: MatchCandidate?
    @State private var layout: KeyboardLayout = Localizer.shared.language == .uk ? .ukrainian : .english
    @FocusState private var focusedKey: String?
    init(itemID: String, api: TorrentTubeAPI, onSaved: @escaping () -> Void) {
        self.api = api
        self.onSaved = onSaved
        _editor = State(initialValue: MatchEditor(itemID: itemID))
    }
    var body: some View {
        HStack(alignment: .top, spacing: 70) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("Fix match")).font(.system(size: 50, weight: .bold))
                queryLine
                HStack(spacing: 16) {
                    Button(editor.type == "tv" ? L("TV Show") : L("Movie")) { editor.type = editor.type == "tv" ? "movie" : "tv" }
                        .buttonStyle(ChipStyle(selected: false))
                    Button(MatchEditor.languageName(editor.language)) {
                        let all = editor.info?.languages ?? [editor.language]
                        editor.language = all[((all.firstIndex(of: editor.language) ?? -1) + 1) % all.count]
                    }
                    .buttonStyle(ChipStyle(selected: false)).accessibilityLabel(L("Metadata language"))
                    if let fileYear = editor.fileYear {
                        Button(editor.year.isEmpty ? L("Any year") : editor.year) { editor.year = editor.year.isEmpty ? fileYear : "" }
                            .buttonStyle(ChipStyle(selected: !editor.year.isEmpty)).accessibilityLabel(L("Year"))
                    }
                }
                SearchKeyboard(layout: $layout, focusedKey: $focusedKey, type: { editor.query += $0 },
                               delete: { if !editor.query.isEmpty { editor.query.removeLast() } })
                if editor.info?.manual == true {
                    Button(L("Match automatically again"), role: .destructive) {
                        Task { if await editor.reset(api: api, catalog: catalog) { onSaved(); dismiss() } }
                    }.buttonStyle(.bordered)
                }
            }
            .frame(width: 620, alignment: .leading)
            .focusSection()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let info = editor.info {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(info.files.prefix(3), id: \.self) { name in
                                Label { Text(name).lineLimit(1).truncationMode(.middle) } icon: { Image(systemName: "film") }
                                    .font(.system(size: 22, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                            }
                            if info.files.count > 3 {
                                Text(L("+ %ld more", info.files.count - 3)).font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
                            }
                            if let current = info.current {
                                Text(L("Now: %@", [current.title, current.year].compactMap { $0 }.joined(separator: " · ")))
                                    .font(.system(size: 22, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    if let searched = editor.searchedFor, !editor.results.isEmpty {
                        Text(L("Results for “%@”", searched)).font(.system(size: 24)).foregroundStyle(.white.opacity(0.6))
                    }
                    if editor.searching && editor.results.isEmpty {
                        LoadingState(text: L("Searching…"), minHeight: 500)
                    } else if editor.results.isEmpty && editor.info != nil {
                        ContentUnavailableView(L("Nothing found"), systemImage: "magnifyingglass",
                                               description: Text(L("Nothing found. Try the original title, another year or another language.")))
                            .frame(maxWidth: .infinity, minHeight: 460)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 270), spacing: 40)], alignment: .leading, spacing: 40) {
                        ForEach(editor.results) { candidate in resultCard(candidate) }
                    }
                }
                // Room for a focused poster to grow without the edge cutting it.
                .padding(.horizontal, 30).padding(.vertical, 40)
            }
            .scrollClipDisabled()
            .focusSection()
        }
        .padding(.leading, TVLayout.edge).padding(.trailing, TVLayout.edge - 30).padding(.top, 50)
        .background(AppBackground())
        .disabled(editor.saving)
        .task { await editor.load(api: api) }
        .task(id: editor.searchKey) {
            guard editor.info != nil else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await editor.search(api: api)
        }
        .alert(L("Use this match?"), isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }), presenting: choice) { candidate in
            Button(L("Use “%@”", candidate.title ?? "")) {
                Task { if await editor.save(candidate, api: api, catalog: catalog) { onSaved(); dismiss() } }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: { candidate in Text(candidate.subtitle) }
        .alert(L("Couldn’t fix the match"), isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(editor.error ?? "") }
    }
    /// What is being searched, large - typed on the keyboard below.
    private var queryLine: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass").font(.system(size: 30, weight: .semibold))
            Text(editor.query.isEmpty ? L("Title") : editor.query)
                .font(.system(size: 34, weight: .semibold)).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 0)
            if editor.searching { ProgressView() }
        }
        .foregroundStyle(focusedKey == "match-input" ? .black : .white)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(focusedKey == "match-input" ? Color.white : Color.white.opacity(0.1), in: Capsule())
        .focusable()
        .focused($focusedKey, equals: "match-input")
        .accessibilityLabel(L("Title")).accessibilityValue(editor.query)
        .accessibilityIdentifier("match-query")
    }
    private func resultCard(_ candidate: MatchCandidate) -> some View {
        Button { choice = candidate } label: {
            VStack(alignment: .leading, spacing: 12) {
                ArtworkView(url: candidate.poster, seed: candidate.title ?? "").aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if candidate.id == editor.info?.current?.id {
                            Text(L("Now")).font(.system(size: 20, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 6)
                                .background(.black.opacity(0.65), in: Capsule()).padding(12)
                        }
                    }
                Text(candidate.title ?? "").font(.system(size: 22, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                Text(candidate.subtitle).font(.system(size: 19)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            }
        }
        .buttonStyle(CinemaCardStyle())
        .accessibilityIdentifier("match-\(candidate.id)")
    }
}
