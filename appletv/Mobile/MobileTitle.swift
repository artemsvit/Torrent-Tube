import SwiftUI

struct MobileTitle: View {
    @Environment(\.mobileEdge) private var edge
    let item: MediaItem
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @State private var expanded = false
    @State private var season = 1
    @State private var episode: Int?
    @State private var episodes: [Episode] = []
    @State private var episodeError: String?
    @State private var loadingEpisodes = false
    @State private var versions: [Release] = []
    @State private var showVersions = false
    @State private var loadingVersions = false
    @State private var versionError: String?
    @State private var findingTrailer = false
    @State private var trailer: Trailer?
    @State private var error: String?
    @State private var playback: PlaybackRequest?
    @State private var pending: PlaybackRequest?
    private var value: MediaItem { catalog.resolved(item) }
    private var details: Details? { catalog.details[item.title] }
    private var saved: Bool { favorites.contains(value, server: api.baseURL) }

    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                VStack(alignment: .leading, spacing: 16) {
                    if let tagline = details?.tagline, !tagline.isEmpty { Text(tagline).font(.headline).italic() }
                    if let overview = details?.overview ?? value.overview, !overview.isEmpty {
                        Text(overview).foregroundStyle(.white.opacity(0.8)).lineLimit(expanded ? nil : 4)
                            .onTapGesture { withAnimation { expanded.toggle() } }
                        Button(L(expanded ? "Show less" : "Read more")) { withAnimation { expanded.toggle() } }.font(.subheadline.weight(.semibold))
                    }
                }.padding(.horizontal, edge).frame(maxWidth: 820, alignment: .leading)
                if details?.mediaType == "tv", let seasons = details?.seasonList, !seasons.isEmpty { episodesSection(seasons) }
                if let people = details?.people, !people.isEmpty { castSection(people) }
                information
                if let recommendations = details?.recommendations, !recommendations.isEmpty {
                    MobileShelf(title: L("More Like This"), items: recommendations.map { rec in
                        var media = MediaItem(title: rec.title, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
                        media.cleanTitle = rec.title; media.poster = rec.poster; media.tmdbId = rec.tmdbId; media.mediaType = rec.mediaType
                        return media
                    })
                }
            }.padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await catalog.enrich([item], api: api, config: config)
            await catalog.loadDetails(item, api: api, config: config)
            if let first = details?.seasonList?.first { season = first.number }
        }
        .task(id: "\(details?.tmdbId ?? 0):\(season)") { await loadEpisodes() }
        .sheet(isPresented: $showVersions, onDismiss: { if let pending { playback = pending; self.pending = nil } }) { versionSheet }
        .fullScreenCover(item: $playback) { MobilePlayback(request: $0, api: api) }
        .fullScreenCover(item: $trailer) { MobileTrailer(trailer: $0, api: api) }
        .alert(L("Unable to play"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    /// The backdrop fills the top of the page and fades into it; the title,
    /// facts and buttons sit over its lower part.
    private var hero: some View {
        let regular = sizeClass == .regular
        return ZStack(alignment: .bottomLeading) {
            MobileBackdrop(url: details?.backdrop ?? value.poster)
            LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.4), .init(color: .black.opacity(0.85), location: 0.78),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                if let kind = mobileKind(value, details) {
                    Text(kind.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(.white.opacity(0.65))
                }
                Text(details?.title ?? value.displayTitle).font(.system(size: regular ? 46 : 32, weight: .heavy))
                    .lineLimit(3).minimumScaleFactor(0.7)
                MobileFacts(item: value, details: details)
                HStack(spacing: 10) {
                    Button { episode = nil; play(source: item.source) } label: {
                        Label(L("Play"), systemImage: "play.fill").font(.headline).frame(maxWidth: regular ? 240 : .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .accessibilityIdentifier("title-play")
                    secondaryActions
                }.padding(.top, 6)
                if item.sourceOverride == nil || (item.releases?.count ?? 0) > 1 {  // a library title saved twice has versions too
                    Button { episode = nil; showVersions = true } label: {
                        Label(L("Choose version"), systemImage: "list.bullet").font(.subheadline.weight(.semibold))
                    }
                    .tint(.white.opacity(0.85)).frame(minHeight: 36)
                    .accessibilityIdentifier("choose-version")
                }
            }
            .padding(.horizontal, edge).padding(.bottom, 4)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(height: regular ? 600 : 540).clipped()
    }

    /// Seasons as a row of chips above the episodes, like the Apple TV app.
    private func episodesSection(_ seasons: [Details.Season]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { selection in
                            let current = selection.number == season
                            Button { withAnimation(.snappy) { season = selection.number } } label: {
                                Text(selection.name.isEmpty ? L("Season %ld", selection.number) : selection.name)
                                    .font(.subheadline.weight(current ? .semibold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(current ? .black : .white)
                                    .background(current ? Color.white : Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(current ? .isSelected : [])
                            .accessibilityIdentifier("season-\(selection.number)")
                        }
                    }.padding(.horizontal, edge)
                }.scrollIndicators(.hidden)
            }
            Text(L("Episodes")).font(.title3.bold()).padding(.horizontal, edge)
            if loadingEpisodes { MobileLoading(text: L("Loading episodes…")).frame(minHeight: 160) }
            if let episodeError { MobileError(message: episodeError) { Task { await loadEpisodes() } } }
            if sizeClass == .regular {
                // iPad: a row of wide episode cards.
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(episodes) { ep in
                            episodeButton(ep) {
                                VStack(alignment: .leading, spacing: 8) {
                                    MobileArtwork(url: ep.still, ratio: 16 / 9).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text("\(ep.number). \(ep.name)").font(.headline).lineLimit(1)
                                    if let overview = ep.overview { Text(overview).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                                }.frame(width: 300)
                            }
                        }
                    }.padding(.horizontal, edge)
                }.scrollIndicators(.hidden)
            } else {
                // iPhone: compact rows - still on the left, text on the right.
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(episodes) { ep in
                        episodeButton(ep) {
                            HStack(alignment: .top, spacing: 12) {
                                MobileArtwork(url: ep.still, ratio: 16 / 9).frame(width: 150).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(ep.number). \(ep.name)").font(.subheadline.weight(.semibold)).lineLimit(2)
                                    if let runtime = ep.runtime { Text(L("%ld min", runtime)).font(.caption).foregroundStyle(.secondary) }
                                    if let overview = ep.overview { Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }.padding(.horizontal, edge)
            }
            if episodes.isEmpty && !loadingEpisodes && episodeError == nil {
                Text(L("Choose a version to see the episodes available to stream.")).font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, edge)
            }
        }
    }
    private func episodeButton<Label: View>(_ ep: Episode, @ViewBuilder label: () -> Label) -> some View {
        Button {
            episode = ep.number
            // Already on the server: play that episode from its folder. Otherwise pick a release first.
            if item.sourceOverride != nil { play(source: item.source) } else { showVersions = true }
        } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityIdentifier("episode-\(ep.number)")
    }

    private func castSection(_ people: [Details.Person]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Cast & Crew")).font(.title3.bold()).padding(.horizontal, edge)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(people.prefix(24).enumerated()), id: \.offset) { _, person in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(Color(white: 0.14))
                                if let photo = person.photo, let url = URL(string: photo) {
                                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                } else {
                                    Text(String(person.name.prefix(1))).font(.title.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                                }
                            }.frame(width: 84, height: 84).clipShape(Circle())
                            Text(person.name).font(.caption.weight(.semibold)).lineLimit(2)
                            if let role = person.role, !role.isEmpty { Text(L(role)).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        }.multilineTextAlignment(.center).frame(width: 96)
                    }
                }.padding(.horizontal, edge)
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var secondaryActions: some View {
        Button {
            findingTrailer = true
            Task {
                defer { findingTrailer = false }
                do {
                    trailer = try await TrailerChoice.find(title: item.title, year: details?.year, known: details?.trailers ?? [], api: api)
                    if trailer == nil { error = L("No trailer was found for this title.") }
                } catch { self.error = error.localizedDescription }
            }
        } label: {
            Group { if findingTrailer { ProgressView() } else { Image(systemName: "play.rectangle") } }
                .font(.headline).frame(width: 30, height: 36)
        }
        .disabled(findingTrailer).buttonStyle(.bordered).tint(.white)
        .accessibilityLabel(L(findingTrailer ? "Finding trailer…" : "Trailer")).accessibilityIdentifier("show-trailers")
        Button { favorites.toggle(value, details: details, server: api.baseURL) } label: {
            Image(systemName: saved ? "heart.fill" : "heart").font(.headline).frame(width: 30, height: 36)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered).tint(.white)
        .accessibilityLabel(L(saved ? "Remove from Favorites" : "Add to Favorites"))
        .accessibilityIdentifier("favorite-toggle")
    }

    @ViewBuilder private var information: some View {
        if let details {
            let rows = infoRows(details)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Information")).font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
                        ForEach(rows, id: \.0) { label, text in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
                                Text(text).font(.subheadline)
                            }
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.padding(.horizontal, edge).frame(maxWidth: 820, alignment: .leading)
            }
        }
    }
    private func infoRows(_ details: Details) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let genres = details.genres, !genres.isEmpty { rows.append((L("Genres"), genres.joined(separator: ", "))) }
        for fact in details.facts ?? [] where !fact.names.isEmpty { rows.append((L(fact.label), fact.names.joined(separator: ", "))) }
        if let countries = details.countries, !countries.isEmpty { rows.append((L("Country"), countries.prefix(3).joined(separator: ", "))) }
        if let certification = details.certification, !certification.isEmpty { rows.append((L("Age rating"), certification)) }
        if let original = details.originalTitle, !original.isEmpty, original != details.title { rows.append((L("Original title"), original)) }
        return rows
    }
    private var versionSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text(value.displayTitle).font(.headline)
                    if let episode { Text(L("Season %ld · Episode %ld", season, episode)).foregroundStyle(.secondary) }
                }
                if loadingVersions { ProgressView(L("Finding versions…")) }
                if let versionError { MobileError(message: versionError) { Task { await loadVersions() } } }
                ForEach(versions) { release in
                    Button { selectVersion(release.source) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(release.title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Text([release.sizeLabel, release.seeders.map { L("%ld seeders", $0) }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
                if versions.isEmpty, !loadingVersions, versionError == nil {
                    if item.source.isPlayable {
                        Button(L("Use this version")) { selectVersion(item.source) }
                    } else { Text(L("No versions found. Try searching for this title.")) }
                }
            }.navigationTitle(L("Choose version")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { showVersions = false } } }
                .task { await loadVersions() }
        }.presentationDetents([.large])
    }
    private func makeRequest(_ source: PlaybackSource) -> PlaybackRequest {
        PlaybackRequest(source: source, title: value.displayTitle, artwork: details?.backdrop ?? value.poster,
                        tmdbID: details?.tmdbId ?? value.tmdbId, season: episode == nil ? nil : season, episode: episode)
    }
    private func play(source: PlaybackSource) {
        guard config.supportsPlayback else { error = L("Update Torrent Tube on your server to stream on this device."); return }
        if !source.isPlayable { showVersions = true }
        else { playback = makeRequest(source) }
    }
    private func selectVersion(_ source: PlaybackSource) {
        guard config.supportsPlayback else { showVersions = false; error = L("Update Torrent Tube on your server to stream on this device."); return }
        pending = makeRequest(source); showVersions = false
    }
    private func loadVersions() async {
        if let releases = item.releases, episode == nil { versions = releases; return }
        loadingVersions = true; versionError = nil
        defer { loadingVersions = false }
        do {
            let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: value.displayTitle), .init(name: "enrich", value: "0")])
            try Task.checkCancellation()
            versions = result.results.map { Release(title: $0.title, magnet: $0.magnet, downloadLink: $0.downloadLink, sizeLabel: $0.sizeLabel, seeders: $0.seeders) }
        } catch is CancellationError {} catch { versionError = error.localizedDescription }
    }
    private func loadEpisodes() async {
        guard let id = details?.tmdbId, details?.mediaType == "tv" else { return }
        let selectedSeason = season
        episodes = []; episodeError = nil; loadingEpisodes = true
        defer { if selectedSeason == season { loadingEpisodes = false } }
        do {
            let result: EpisodeResponse = try await api.request("api/episodes", query: [.init(name: "id", value: String(id)), .init(name: "season", value: String(selectedSeason))])
            try Task.checkCancellation()
            if selectedSeason == season { episodes = result.episodes }
        } catch is CancellationError {} catch { if selectedSeason == season { episodeError = error.localizedDescription } }
    }
}
