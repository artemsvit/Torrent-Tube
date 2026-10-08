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
    @State private var trailerError: String?
    @State private var season = 1
    @State private var selectedEpisode: Int?
    @State private var episodes: [Episode] = []
    @State private var episodeLoading = false
    @State private var playback: PlaybackRequest?
    @State private var pendingPlayback: PlaybackRequest?
    @State private var showServerNotice = false
    private var value: MediaItem { catalog.resolved(item) }
    private var details: Details? { catalog.details[item.title] }
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
    @Environment(\.backToTop) private var backToTop
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
                CinemaHero(item: value, details: details, height: 760, showsOverview: false) {
                    HStack(spacing: 28) {
                        Button { play() } label: { Label(L("Play"), systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).accessibilityIdentifier("title-play")
                        Button { playTrailer() } label: { Label(findingTrailer ? L("Finding trailer…") : L("Trailer"), systemImage: "play.rectangle") }
                            .disabled(findingTrailer)
                            .buttonStyle(.bordered).tint(.white).accessibilityIdentifier("show-trailers")
                        FavoriteButton(item: value, details: details, server: api.baseURL)
                        if item.sourceOverride == nil || (item.releases?.count ?? 0) > 1 {  // a library title saved twice has versions too
                            Button(L("Choose version")) { selectedEpisode = nil; showVersions = true }.buttonStyle(.bordered).tint(.white)
                        }
                    }
                }
                if let tagline = details?.tagline, !tagline.isEmpty {
                    Text(tagline).font(.system(size: 27, weight: .semibold)).italic().foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, TVLayout.edge).padding(.bottom, -18)
                }
                if let overview = details?.overview ?? value.overview, !overview.isEmpty {
                    Text(overview).font(.system(size: 27)).foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: 1300, alignment: .leading).padding(.horizontal, TVLayout.edge)
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
                                        Button { season = selection.number } label: {
                                            Text(selection.name.isEmpty ? L("Season %ld", selection.number) : selection.name)
                                                .fontWeight(current ? .bold : .medium)
                                        }
                                        .buttonStyle(.bordered).tint(current ? .torrentAccent : .white)
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
                                        selectedEpisode = episode.number
                                        // Already on the server: play that episode from its folder.
                                        if item.sourceOverride != nil {
                                            if config.supportsPlayback { playback = request(source: item.source) } else { showServerNotice = true }
                                        } else { showVersions = true }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 14) {
                                            ArtworkView(url: episode.still).frame(width: 380, height: 215).clipShape(RoundedRectangle(cornerRadius: 12))
                                            Text("\(episode.number). \(episode.name)").font(.system(size: 25, weight: .semibold)).lineLimit(2)
                                            if let runtime = episode.runtime { Text(L("%ld min", runtime)).font(.system(size: 21)).foregroundStyle(.secondary) }
                                            if let overview = episode.overview { Text(overview).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(3) }
                                        }.frame(width: 380, alignment: .leading)
                                    }.buttonStyle(CinemaCardStyle())
                                }
                            }.padding(.horizontal, TVLayout.edge).padding(.vertical, 18)
                        }.focusSection()
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
        .ignoresSafeArea(edges: [.top, .horizontal])
        .background(.black)
        // Menu/Back: straight to the tab's top level.
        .onExitCommand { backToTop() }
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
        .alert(L("No trailer"), isPresented: Binding(get: { trailerError != nil }, set: { if !$0 { trailerError = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(trailerError ?? "") }
        .fullScreenCover(item: $playback) { request in PlaybackLauncher(request: request, api: api) }
        .task {
            await catalog.enrich([item], api: api, config: config)
            await catalog.loadDetails(item, api: api, config: config)
            if let first = details?.seasonList?.first { season = first.number }
        }
        .task(id: "\(details?.tmdbId ?? 0):\(season)") { await loadEpisodes() }
    }
    private func play() {
        guard config.supportsPlayback else { showServerNotice = true; return }
        selectedEpisode = nil
        playback = request(source: item.source)
    }
    private func request(source: PlaybackSource) -> PlaybackRequest {
        PlaybackRequest(source: source, title: value.displayTitle, artwork: details?.backdrop ?? value.poster,
                        tmdbID: details?.tmdbId ?? value.tmdbId, season: selectedEpisode == nil ? nil : season, episode: selectedEpisode)
    }
    private func loadVersions() async {
        if let provided = item.releases, selectedEpisode == nil { versions = provided; return }
        versionsLoading = true; versionError = nil
        defer { versionsLoading = false }
        do {
            let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: value.displayTitle), .init(name: "enrich", value: "0")])
            try Task.checkCancellation()
            versions = result.results.map { Release(title: $0.title, magnet: $0.magnet, downloadLink: $0.downloadLink, sizeLabel: $0.sizeLabel, seeders: $0.seeders) }
        } catch is CancellationError {} catch { versionError = error.localizedDescription }
    }
    private func loadEpisodes() async {
        guard let id = details?.tmdbId, details?.mediaType == "tv" else { return }
        let requestedSeason = season
        episodeLoading = true; episodes = []
        defer { if requestedSeason == season { episodeLoading = false } }
        if let response: EpisodeResponse = try? await api.request("api/episodes", query: [.init(name: "id", value: String(id)), .init(name: "season", value: String(requestedSeason))]), !Task.isCancelled, requestedSeason == season {
            episodes = response.episodes
        }
    }
}
