import Foundation
import Observation

/// Owns only this viewer's stream lease. Both platforms use the same selection,
/// resume, heartbeat and cleanup rules; the views only present these states.
@MainActor @Observable
final class PlaybackCoordinator {
    let request: PlaybackRequest
    let api: TorrentTubeAPI
    var history: ResumeHistory?
    var prepared: PreparedPlayback?
    var session: PlaybackSession?
    var controller: EmbeddedPlayer?
    var resumeEntry: ResumeEntry?
    var episodeMetadata: [Int: [Episode]] = [:]
    var loading = true
    var error: String?
    var streamStatus: StreamStatus?
    var suspended = false
    var completed = false
    /// The opening of this episode, when the server found one: the player
    /// offers "Skip intro" while it plays.
    var intro: ClosedRange<Double>?
    private var selectedSource: PlaybackSource?
    private var closed = false
    private var operation = UUID()
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var progress: Task<Void, Never>?
    @ObservationIgnored private var introLookup: Task<Void, Never>?

    init(request: PlaybackRequest, api: TorrentTubeAPI) {
        self.request = request
        self.api = api
    }

    var episodeLabel: String? {
        let identity: EpisodeIdentity?
        if let session {
            let file = prepared?.files.first { $0.index == session.file }
            identity = file.flatMap(identity(of:)) ?? EpisodeIdentity.parse(session.name)
        } else {
            identity = nil
        }
        if let identity { return identity.label }
        if let season = request.season, let episode = request.episode {
            return L("Season %ld · Episode %ld", season, episode)
        }
        return nil
    }

    static func selectedFile(request: PlaybackRequest, prepared: PreparedPlayback) -> Int? {
        if let season = request.season, let episode = request.episode {
            // A file with two episodes in it plays for either of them.
            let matches = episodeMatches(request: request, prepared: prepared, season: season, episode: episode)
            return matches.count == 1 ? matches.first?.index : nil
        }
        if let file = request.source.file, prepared.files.contains(where: { $0.index == file }) { return file }
        if prepared.files.count == 1 { return prepared.files.first?.index }
        // A season or a whole series: start at its first episode instead of asking.
        let episodes = prepared.files.compactMap { file in identity(of: file, in: request.source).map { (file.index, $0) } }
        guard episodes.count > 1 else { return nil }
        return episodes.min { ($0.1.season, $0.1.episode) < ($1.1.season, $1.1.episode) }?.0
    }

    /// The server's season and episode for the file, else read from its name
    /// and the folders above it.
    static func identity(of file: VideoFile, in source: PlaybackSource) -> EpisodeIdentity? {
        if let season = file.season, let episode = file.episode {
            return EpisodeIdentity(season: season, episode: episode, lastEpisode: file.lastEpisode)
        }
        return EpisodeIdentity.parse(name: file.name, path: file.path ?? source.path.map { $0 + "/" + file.name })
    }
    private func identity(of file: VideoFile) -> EpisodeIdentity? { Self.identity(of: file, in: selectedSource ?? request.source) }

    /// The files that hold this episode: one normally, several when the
    /// folder has more than one copy (then the person chooses).
    static func episodeMatches(request: PlaybackRequest, prepared: PreparedPlayback, season: Int, episode: Int) -> [VideoFile] {
        prepared.files.filter { identity(of: $0, in: request.source)?.covers(season: season, episode: episode) == true }
    }

    /// The file to play after `current`: the next episode by season and
    /// number when the names say so, else the next file in the list.
    static func nextFile(after current: Int, in files: [VideoFile]) -> Int? {
        guard files.count > 1 else { return nil }
        let episodes = files.compactMap { file in file.episodeIdentity.map { (file.index, $0) } }
        if episodes.count > 1, let playing = episodes.first(where: { $0.0 == current })?.1 {
            return episodes.filter { ($0.1.season, $0.1.episode) > (playing.season, playing.lastEpisode) }
                .min { ($0.1.season, $0.1.episode) < ($1.1.season, $1.1.episode) }?.0
        }
        guard let position = files.firstIndex(where: { $0.index == current }), position + 1 < files.count else { return nil }
        return files[position + 1].index
    }

    func prepare() async {
        guard !closed else { return }
        savePosition()
        release()
        let current = UUID(); operation = current
        loading = true; error = nil; prepared = nil; resumeEntry = nil; suspended = false
        defer { if current == operation { loading = false } }
        do {
            let source = selectedSource ?? request.source
            let result: PreparedPlayback = try await api.post("api/playback/prepare", body: source)
            try Task.checkCancellation()
            guard current == operation, !closed else { return }
            prepared = result
            guard !result.files.isEmpty else { throw APIError(message: L("This torrent contains no supported video files.")) }
            var selection = request
            if let selectedSource { selection = PlaybackRequest(source: selectedSource, title: request.title, artwork: request.artwork, tmdbID: request.tmdbID) }
            if let file = Self.selectedFile(request: selection, prepared: result) {
                await start(file: file)
            } else if let season = selection.season, let episode = selection.episode,
                      Self.episodeMatches(request: selection, prepared: result, season: season, episode: episode).isEmpty {
                throw APIError(message: L("The selected episode could not be found in this source."))
            }
            // Otherwise several copies of the episode (or no episode asked for): the file list asks.
        } catch is CancellationError {} catch {
            if current == operation { self.error = error.localizedDescription }
        }
    }

    func loadEpisodeMetadata() async {
        guard let id = request.tmdbID, let prepared else { return }
        for season in Set(prepared.files.compactMap { $0.episodeIdentity?.season }) {
            if let response: EpisodeResponse = try? await api.request("api/episodes", query: [.init(name: "id", value: String(id)), .init(name: "season", value: String(season))]), !Task.isCancelled {
                episodeMetadata[season] = response.episodes
            }
        }
    }

    /// `continuing`: the next episode after one ended - play at once (from
    /// its saved place, if any) instead of asking.
    func start(file: Int, continuing: Bool = false) async {
        guard !closed, !suspended else { return }
        let current = UUID(); operation = current
        loading = true; error = nil
        defer { if current == operation { loading = false } }
        var source = selectedSource ?? request.source
        source.file = file
        do {
            let result: PlaybackSession = try await api.post("api/playback/sessions", body: source)
            if closed || Task.isCancelled || current != operation || suspended {
                try? await api.command("api/playback/sessions/\(result.session)", method: "DELETE")
                return
            }
            session = result
            selectedSource = source
            beginHeartbeat(result)
            loadIntro(file: file, source: source)
            if let prior = history?.entry(server: api.baseURL, torrentID: result.id, file: result.file) {
                if continuing { openPlayer(at: prior.seconds) } else { resumeEntry = prior }
            } else { openPlayer(at: 0) }
        } catch is CancellationError {} catch {
            if current == operation { self.error = error.localizedDescription }
        }
    }

    /// Library episodes only: the server needs the whole file on disk.
    private func loadIntro(file: Int, source: PlaybackSource) {
        introLookup?.cancel(); intro = nil
        guard source.path != nil, let path = prepared?.files.first(where: { $0.index == file })?.path else { return }
        introLookup = Task { [weak self, api] in
            // The first look at a season takes a little while; ask again until it is done.
            for _ in 0..<15 {
                guard let response: IntroResponse = try? await api.request("api/intro", query: [.init(name: "path", value: path)]),
                      !Task.isCancelled else { return }
                if response.status == "ready", let start = response.start, let end = response.end, end > start {
                    self?.intro = start...end
                    return
                }
                guard response.status == "pending" else { return }
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
            }
        }
    }

    /// After a season's last episode: the first episode of the next season,
    /// from the title's other folders on the server. False when there is none.
    private func continueWithNextSeason(after playing: EpisodeIdentity) async -> Bool {
        let current = (selectedSource ?? request.source).path
        var folders: [(PlaybackSource, PreparedPlayback)] = []
        for source in request.seasonSources where source.path != current {
            guard !closed, let result: PreparedPlayback = try? await api.post("api/playback/prepare", body: source) else { continue }
            folders.append((source, result))
        }
        guard let next = Self.nextSeasonStart(after: playing, in: folders), !closed, !suspended else { return false }
        selectedSource = folders[next.folder].0
        prepared = folders[next.folder].1
        await start(file: next.file, continuing: true)
        return true
    }

    /// In the title's other folders: the earliest episode of a later season
    /// (a copy of the season just watched never counts). Nil when there is none.
    static func nextSeasonStart(after playing: EpisodeIdentity, in folders: [(PlaybackSource, PreparedPlayback)]) -> (folder: Int, file: Int)? {
        var best: (folder: Int, file: Int, episode: EpisodeIdentity)?
        for (index, folder) in folders.enumerated() {
            for file in folder.1.files {
                guard let found = file.episodeIdentity, found.season > playing.season else { continue }
                if let best, (best.episode.season, best.episode.episode) <= (found.season, found.episode) { continue }
                best = (index, file.index, found)
            }
        }
        return best.map { ($0.folder, $0.file) }
    }

    func openPlayer(at seconds: Double) {
        guard let session, !closed, !suspended else { return }
        do {
            let player = EmbeddedPlayer(url: try api.mediaURL(session.url), resumePosition: seconds)
            controller = player; resumeEntry = nil
            progress?.cancel()
            progress = Task { [weak self] in
                var ticks = 0
                while !Task.isCancelled {
                    guard let self else { return }
                    player.refresh(); ticks += 1
                    if ticks % 10 == 0 { self.savePosition() }
                    if player.ended {
                        self.savePosition(completed: true)
                        let finished = self.session?.file
                        self.release()
                        let files = self.prepared?.files ?? []
                        if let finished, let next = Self.nextFile(after: finished, in: files) {
                            // A new task: this one was cancelled by release().
                            Task { await self.start(file: next, continuing: true) }
                        } else if let finished, let playing = files.first(where: { $0.index == finished })?.episodeIdentity,
                                  !self.request.seasonSources.isEmpty {
                            // The last episode of this folder: the next season may be in another.
                            Task { if await !self.continueWithNextSeason(after: playing) { self.completed = true } }
                        } else {
                            self.completed = true
                        }
                        return
                    }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func beginHeartbeat(_ session: PlaybackSession) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self, api] in
            var lastSuccess = Date()
            while !Task.isCancelled {
                do {
                    let status: StreamStatus = try await api.request("api/playback/sessions/\(session.session)", method: "POST", body: Data("{}".utf8))
                    guard !Task.isCancelled, self?.session?.session == session.session else { return }
                    self?.streamStatus = status
                    lastSuccess = Date()
                } catch is CancellationError { return } catch {
                    guard !Task.isCancelled else { return }
                    if Date().timeIntervalSince(lastSuccess) > 45 || error is APIError {
                        self?.controller?.pause()
                        self?.error = error.localizedDescription
                        self?.controller?.failure = error.localizedDescription
                        return
                    }
                }
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            }
        }
    }

    func savePosition(completed: Bool = false) {
        guard let session, let controller else { return }
        history?.save(server: api.baseURL, session: session, title: request.title, source: selectedSource ?? request.source,
                      seconds: controller.seconds, duration: controller.duration, artwork: request.artwork, completed: completed || controller.ended)
    }

    func suspend() {
        guard !closed, !suspended else { return }
        controller?.refresh()
        savePosition()
        suspended = true
        operation = UUID()
        loading = false
        release()
    }

    func close() {
        guard !closed else { return }
        savePosition()
        closed = true; operation = UUID()
        release()
    }

    private func release() {
        introLookup?.cancel(); introLookup = nil; intro = nil
        heartbeat?.cancel(); heartbeat = nil
        progress?.cancel(); progress = nil
        controller?.stop(); controller = nil
        if let session {
            Task { [api] in try? await api.command("api/playback/sessions/\(session.session)", method: "DELETE") }
        }
        session = nil; streamStatus = nil
    }
}
