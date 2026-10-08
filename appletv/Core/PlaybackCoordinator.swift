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
    private var selectedSource: PlaybackSource?
    private var closed = false
    private var operation = UUID()
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var progress: Task<Void, Never>?

    init(request: PlaybackRequest, api: TorrentTubeAPI) {
        self.request = request
        self.api = api
    }

    static func selectedFile(request: PlaybackRequest, prepared: PreparedPlayback) -> Int? {
        if let season = request.season, let episode = request.episode {
            let matches = prepared.files.filter { EpisodeIdentity.parse($0.name) == EpisodeIdentity(season: season, episode: episode) }
            return matches.count == 1 ? matches.first?.index : nil
        }
        if let file = request.source.file, prepared.files.contains(where: { $0.index == file }) { return file }
        return prepared.files.count == 1 ? prepared.files.first?.index : nil
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
            if let file = Self.selectedFile(request: selection, prepared: result) { await start(file: file) }
        } catch is CancellationError {} catch {
            if current == operation { self.error = error.localizedDescription }
        }
    }

    func loadEpisodeMetadata() async {
        guard let id = request.tmdbID, let prepared else { return }
        for season in Set(prepared.files.compactMap { EpisodeIdentity.parse($0.name)?.season }) {
            if let response: EpisodeResponse = try? await api.request("api/episodes", query: [.init(name: "id", value: String(id)), .init(name: "season", value: String(season))]), !Task.isCancelled {
                episodeMetadata[season] = response.episodes
            }
        }
    }

    func start(file: Int) async {
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
            if let prior = history?.entry(server: api.baseURL, torrentID: result.id, file: result.file) {
                resumeEntry = prior
            } else { openPlayer(at: 0) }
        } catch is CancellationError {} catch {
            if current == operation { self.error = error.localizedDescription }
        }
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
                    if player.ended { self.savePosition(completed: true); self.completed = true; self.release(); return }
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
        heartbeat?.cancel(); heartbeat = nil
        progress?.cancel(); progress = nil
        controller?.stop(); controller = nil
        if let session {
            Task { [api] in try? await api.command("api/playback/sessions/\(session.session)", method: "DELETE") }
        }
        session = nil; streamStatus = nil
    }
}
