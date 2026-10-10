import SwiftUI

struct MobileTitle: View {
    @Environment(\.mobileEdge) private var edge
    let item: MediaItem
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @State private var expanded = false
    @State private var heroGrowth: CGFloat = 0
    @State private var season = 1
    /// Set once, so the season stays when the page appears again.
    @State private var seasonPicked = false
    @State private var launchingEpisode: Int?
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { screen in
            let heroHeight = HeroLayout.bannerHeight(screenHeight: screen.size.height, sizeClass: sizeClass)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    hero(height: heroHeight).padding(.top, -refreshSpinnerRoom)
                    if details?.mediaType == "tv", let seasons = details?.seasonList, !seasons.isEmpty { episodesSection(seasons) }
                    if let people = details?.people, !people.isEmpty { castSection(people) }
                    information(width: screen.size.width)
                    if let recommendations = details?.recommendations, !recommendations.isEmpty {
                        MobileShelf(title: L("More Like This"), items: recommendations.map { rec in
                            var media = MediaItem(title: rec.title, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
                            media.cleanTitle = rec.title; media.poster = rec.poster; media.tmdbId = rec.tmdbId; media.mediaType = rec.mediaType
                            return media
                        })
                    }
                }.padding(.bottom, 32)
            }
            .refreshable {
                await catalog.loadDetails(item, api: api, config: config, refresh: true)
                await loadEpisodes()
            }
            .contentMargins(.top, refreshSpinnerRoom, for: .scrollContent)
            .pulledFill(height: heroHeight) { heroArt(regular: sizeClass == .regular) }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        #if !os(macOS)
        .toolbar {
            // Opposite the Back button, top right.
            ToolbarItem(placement: .topBarTrailing) { favoriteButton }
        }
        #endif
        #if DEBUG
        .task { if UserDefaults.standard.bool(forKey: "macExpand") { expanded = true } }  // screenshots: -macExpand YES
        #endif
        .task {
            await catalog.enrich([item], api: api, config: config)
            await catalog.loadDetails(item, api: api, config: config)
            if !seasonPicked, let first = details?.seasonList?.first { season = first.number; seasonPicked = true }
        }
        .task(id: "\(details?.tmdbId ?? 0):\(season)") { await loadEpisodes() }
        .onChange(of: season) { launchingEpisode = nil }
        .task(id: launchingEpisode) {
            guard let number = launchingEpisode else { return }
            episode = number
            defer { if !Task.isCancelled { launchingEpisode = nil } }
            guard config.supportsPlayback else { error = L("Update Torrent Tube on your server to stream on this device."); return }
            do {
                let source = try await ReleaseChoice.resolveEpisodeSource(for: item, title: value.displayTitle,
                    original: details?.originalTitle, tmdbID: details?.tmdbId ?? value.tmdbId,
                    season: season, episode: number, api: api)
                try Task.checkCancellation()
                play(source: source)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        .versionsPresentation(isPresented: $showVersions, onDismiss: { if let pending { playback = pending; self.pending = nil } }) { versionSheet }
        .fullScreenCover(item: $playback) { MobilePlayback(request: $0, api: api) }
        .fullScreenCover(item: $trailer) { MobileTrailer(trailer: $0, api: api) }
        .alert(L("Unable to play"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func heroArt(regular: Bool) -> some View {
        ZStack {
            if regular {
                MobileBackdrop(url: details?.backdrop ?? value.poster, placeholder: value.displayTitle)
            } else if let poster = value.poster.map({ higherResolution($0, backdrop: false).replacingOccurrences(of: "/w500/", with: "/w780/") }) {
                // A phone is tall: the poster fits it better than the wide backdrop.
                HeroBackdrop(url: URL(string: poster), alignment: .top, placeholder: value.displayTitle)
            } else {
                MobileBackdrop(url: details?.backdrop, placeholder: value.displayTitle)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .black.opacity(0.75), location: 0.8),
                                   .init(color: .black, location: 1.0)], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0),
                                   .init(color: .clear, location: 0.6)], startPoint: .leading, endPoint: .trailing)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.45),
                .init(color: .white.opacity(0.85), location: 0.65),
                .init(color: .white.opacity(0.35), location: 0.86),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    /// The backdrop fills the top of the page and fades into it; the title,
    /// facts and buttons sit over its lower part.
    private func hero(height: CGFloat) -> some View {
        let regular = sizeClass == .regular
        return ZStack(alignment: .bottomLeading) {
            // Pulled down past the top, the area above the image is filled from its top edge.
            HeroArtFrame(height: height) { heroArt(regular: regular) }
                .frame(maxHeight: .infinity, alignment: .top)  // the image keeps its size
            HeroInfo(kind: mobileKind(value, details), title: details?.title ?? value.displayTitle, item: value, details: details,
                     overview: details?.overview ?? value.overview, tagline: details?.tagline, expanded: expanded,
                     // No animation: the text opens downward at once.
                     toggleMore: (details?.overview ?? value.overview ?? "").count > 160 ? { expanded.toggle() } : nil,
                     growth: $heroGrowth) {
                Button { episode = nil; play(source: item.source) } label: {
                    Label(L("Play"), systemImage: "play.fill").font(HeroFont.button).frame(maxWidth: regular ? 220 : .infinity, minHeight: HeroFont.buttonHeight)
                }
                .primaryHeroButton()
                .accessibilityIdentifier("title-play")
                secondaryActions
                if item.sourceOverride == nil || (item.releases?.count ?? 0) > 1 {  // a library title saved twice has versions too
                    Button { episode = nil; showVersions = true } label: {
                        Image(systemName: "list.bullet").font(HeroFont.button).frame(width: 30, height: HeroFont.buttonHeight)
                    }
                    .hapticButtonStyle(BorderedButtonStyle()).tint(.white)
                    .help(L("Choose version")).accessibilityLabel(L("Choose version"))
                    .accessibilityIdentifier("choose-version")
                }
            }
            .padding(.horizontal, edge).padding(.bottom, 12)
        }
        .frame(height: height + heroGrowth)
        // Clips the sides and bottom only: the art above the top edge shows when the page is pulled down.
        .mask(Rectangle().padding(.top, -1500))
    }

    /// Seasons as a row of chips above the episodes, like the Apple TV app.
    private func episodesSection(_ seasons: [Details.Season]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { selection in
                            let current = selection.number == season
                            Button { withAnimation(.snappy) { season = selection.number; seasonPicked = true } } label: {
                                Text(selection.name.isEmpty ? L("Season %ld", selection.number) : selection.name)
                                    .font(HeroFont.chip)
                                    .padding(HeroFont.chipPadding)
                                    .foregroundStyle(current ? .black : .white)
                                    .background(current ? Color.white : Color.white.opacity(0.12), in: Capsule())
                            }
                            .hapticButtonStyle(PlainButtonStyle())
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
                            // As on Apple TV: the length on the picture, the whole name below.
                            episodeButton(ep) {
                                VStack(alignment: .leading, spacing: 8) {
                                    // A fixed size: a name on two lines must not shrink the picture.
                                    episodeStill(ep, cornerRadius: 12).frame(width: 300, height: 169)
                                    Text("\(ep.number). \(ep.name)").font(MobileStyle.itemTitle(.headline, weight: .semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(width: 300, alignment: .topLeading)
                        }
                    }.padding(.horizontal, edge)
                }.scrollIndicators(.hidden)
            } else {
                // iPhone: compact rows - still on the left, text on the right.
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(episodes) { ep in
                        episodeButton(ep) {
                            HStack(alignment: .top, spacing: 12) {
                                episodeStill(ep, cornerRadius: 10).frame(width: 150, height: 84)
                                Text("\(ep.number). \(ep.name)").font(MobileStyle.itemTitle(.subheadline.weight(.semibold), weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
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
    /// The episode's picture with its length in the corner, as on Apple TV.
    private func episodeStill(_ ep: Episode, cornerRadius: CGFloat) -> some View {
        MobileArtwork(url: ep.still, ratio: 16 / 9, seed: "\(value.displayTitle) \(ep.number)")
            .overlay(alignment: .bottomTrailing) {
                if let runtime = ep.runtime {
                    Text(L("%ld min", runtime)).font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    private func episodeButton<Label: View>(_ ep: Episode, @ViewBuilder label: () -> Label) -> some View {
        Button {
            launchingEpisode = ep.number
        } label: { label().contentShape(Rectangle()) }
            .hapticButtonStyle(PlainButtonStyle()).accessibilityIdentifier("episode-\(ep.number)")
            .overlay { if launchingEpisode == ep.number { ProgressView().tint(.white) } }
    }

    /// A cast photo opens that person's films and shows.
    @ViewBuilder private func personLink<Content: View>(_ person: Details.Person, @ViewBuilder _ content: () -> Content) -> some View {
        if let route = person.route {
            NavigationLink(value: route) { content() }
                .hapticButtonStyle(PlainButtonStyle())
                .accessibilityIdentifier("person-\(route.id)")
        } else {
            content()
        }
    }

    private func castSection(_ people: [Details.Person]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Cast & Crew")).font(.title3.bold()).padding(.horizontal, edge)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(people.prefix(24).enumerated()), id: \.offset) { _, person in
                        personLink(person) {
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
                    }
                }.padding(.horizontal, edge)
            }.scrollIndicators(.hidden)
        }
    }

    private var favoriteButton: some View {
        Button { favorites.toggle(value, details: details, server: api.baseURL) } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
        }
        .tint(.white)
        .accessibilityLabel(L(saved ? "Remove from Favorites" : "Add to Favorites"))
        .accessibilityIdentifier("favorite-toggle")
        .sensoryFeedback(.success, trigger: saved)  // a light tap when saved or removed
    }

    @ViewBuilder private var secondaryActions: some View {
        Button {
            findingTrailer = true
            Task {
                defer { findingTrailer = false }
                do {
                    trailer = try await TrailerChoice.find(title: item.title, year: details?.year, known: details?.trailers ?? [], api: api)
                    if trailer == nil { error = L("No trailer was found for this title.") }
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
        } label: {
            // iPad and Mac name it, as on Apple TV; iPhone keeps the icon.
            HStack(spacing: 8) {
                Group { if findingTrailer { ProgressView() } else { Image(systemName: "play.rectangle") } }
                if sizeClass == .regular { Text(L("Trailer")) }
            }
            .font(HeroFont.button).padding(.horizontal, sizeClass == .regular ? 10 : 0)
            .frame(minWidth: 30, minHeight: HeroFont.buttonHeight)
        }
        .disabled(findingTrailer).hapticButtonStyle(BorderedButtonStyle()).tint(.white)
        .accessibilityLabel(L(findingTrailer ? "Finding trailer…" : "Trailer")).accessibilityIdentifier("show-trailers")
        #if os(macOS)
        // The Mac has no navigation bar here, so the heart stays with the other actions.
        Button { favorites.toggle(value, details: details, server: api.baseURL) } label: {
            Image(systemName: saved ? "heart.fill" : "heart").font(HeroFont.button).frame(width: 30, height: HeroFont.buttonHeight)
                .contentTransition(.symbolEffect(.replace))
        }
        .hapticButtonStyle(BorderedButtonStyle()).tint(.white)
        .accessibilityLabel(L(saved ? "Remove from Favorites" : "Add to Favorites"))
        .accessibilityIdentifier("favorite-toggle")
        #endif
    }

    @ViewBuilder private func information(width: CGFloat) -> some View {
        if let details {
            let rows = infoRows(details)
            if !rows.isEmpty {
                let count = typeSize.isAccessibilitySize ? 1 : (sizeClass == .regular
                    ? min(rows.count, max(2, Int((width - edge * 2 - 40) / 190))) : 2)
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Information")).font(.title3.bold())
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .topLeading), count: count), alignment: .leading, spacing: 24) {
                        ForEach(rows, id: \.0) { label, text in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(label.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                                    .foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                                Text(text).font(.body).foregroundStyle(.white.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("title-information")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, edge)
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
    private func releaseTags(from title: String) -> [String] {
        var tags: [String] = []
        let lower = title.lowercased()
        if lower.contains("2160p") || lower.contains("4k") { tags.append("4K") }
        else if lower.contains("1080p") { tags.append("1080p") }
        else if lower.contains("720p") { tags.append("720p") }

        if lower.contains("dv") || lower.contains("dolby vision") { tags.append("DV") }
        if lower.contains("hdr10+") { tags.append("HDR10+") }
        else if lower.contains("hdr") { tags.append("HDR") }

        if lower.contains("ukr") || lower.contains("укр") { tags.append("UKR") }
        return tags
    }

    private func versionCard(_ release: Release) -> some View {
        Button {
            selectVersion(release.source)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.torrentAccent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    Text(release.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    let tags = releaseTags(from: release.title)
                    if !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(tag == "4K" ? Color.torrentAccent.opacity(0.35) : Color.white.opacity(0.12), in: Capsule())
                                    .foregroundStyle(tag == "4K" ? Color.white : Color.white.opacity(0.9))
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        if let size = release.sizeLabel, !size.isEmpty {
                            Label(size, systemImage: "internaldrive")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if let seeders = release.seeders {
                            Label(L("%ld seeders", seeders), systemImage: "person.2.fill")
                                .font(.caption)
                                .foregroundStyle(seeders > 0 ? Color.green.opacity(0.9) : .white.opacity(0.45))
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .hapticButtonStyle(PlainButtonStyle())
    }

    private var versionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    #if os(macOS)
                    HStack {
                        Text(L("Choose version")).font(.system(size: 26, weight: .bold))
                        Spacer()
                        Button(L("Cancel")) { showVersions = false }.hapticButtonStyle(BorderedButtonStyle()).keyboardShortcut(.cancelAction)
                    }
                    .padding(.top, 24)
                    #endif
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let episode {
                            Text(L("Season %ld · Episode %ld", season, episode))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )

                    if loadingVersions {
                        HStack {
                            Spacer()
                            ProgressView(L("Finding versions…"))
                                .tint(.white)
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    }

                    if let versionError {
                        MobileError(message: versionError) { Task { await loadVersions() } }
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(versions) { release in
                            versionCard(release)
                        }
                    }

                    if versions.isEmpty, !loadingVersions, versionError == nil {
                        if item.source.isPlayable {
                            Button {
                                selectVersion(item.source)
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text(L("Use this version"))
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.torrentAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .hapticButtonStyle(PlainButtonStyle())
                        } else {
                            Text(L("No versions found. Try searching for this title."))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppBackground())
            .navigationTitle(L("Choose version"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { showVersions = false }
                        .tint(.white)
                        .accessibilityIdentifier("cancel-version")
                }
            }
            .task { await loadVersions() }
        }
        .presentationDetents([.large])
        .presentationBackground { AppBackground() }
    }
    private func makeRequest(_ source: PlaybackSource) -> PlaybackRequest {
        PlaybackRequest(source: source, title: value.displayTitle, artwork: details?.backdrop ?? value.poster,
                        tmdbID: details?.tmdbId ?? value.tmdbId, season: episode == nil ? nil : season, episode: episode,
                        seasonSources: item.librarySources)
    }
    private func play(source: PlaybackSource) {
        guard config.supportsPlayback else { error = L("Update Torrent Tube on your server to stream on this device."); return }
        if !source.isPlayable { showVersions = true }
        else { playback = makeRequest(source) }
    }
    private func selectVersion(_ source: PlaybackSource) {
        guard config.supportsPlayback else { showVersions = false; error = L("Update Torrent Tube on your server to stream on this device."); return }
        pending = makeRequest(source); showVersions = false
        // Remembered for this series: its other episodes play from it at once.
        if details?.mediaType == "tv" {
            ReleaseChoice.remember(source, title: versions.first { $0.source == source }?.title ?? value.title, for: details?.tmdbId ?? value.tmdbId)
        }
    }
    private func loadVersions() async {
        if let releases = item.releases, episode == nil { versions = releases; return }
        loadingVersions = true; versionError = nil
        defer { loadingVersions = false }
        do {
            // The Ukrainian and the original title; releases are often named in English.
            versions = try await ReleaseChoice.search(title: value.displayTitle, original: details?.originalTitle,
                                                      season: episode == nil ? nil : season, api: api)
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

