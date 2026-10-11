import Foundation
import Observation

struct ResumeEntry: Codable, Identifiable {
    let id: String
    let server: String
    let torrentID: String
    let file: Int
    let title: String
    let source: PlaybackSource
    var artwork: String? = nil
    var seconds: Double
    var duration: Double
    var updatedAt: Date
    var displayPosition: String { Self.time(seconds) }
    static func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Wire dates use Unix seconds, independent of the device's server address.
private struct RemoteResume: Codable, Equatable {
    let torrentID: String
    let file: Int
    let updatedAt: Double
    var removed: Bool = false
    var title: String?
    var source: PlaybackSource?
    var artwork: String?
    var seconds: Double?
    var duration: Double?
    // Explicit spelling also lets convertFromSnakeCase decode torrent_id.
    enum CodingKeys: String, CodingKey {
        case torrentID = "torrentId", file, updatedAt, removed, title, source, artwork, seconds, duration
    }
    init(_ entry: ResumeEntry, removed: Bool = false) {
        torrentID = entry.torrentID; file = entry.file
        updatedAt = entry.updatedAt.timeIntervalSince1970
        self.removed = removed; title = entry.title; source = entry.source
        artwork = entry.artwork; seconds = entry.seconds; duration = entry.duration
    }
    func local(server: URL) -> ResumeEntry? {
        guard !removed, let title, let source, let seconds, let duration,
              seconds.isFinite, duration.isFinite, updatedAt.isFinite,
              seconds >= 10, duration > 0, seconds < duration - 15 else { return nil }
        return ResumeEntry(id: ResumeHistory.key(server: server, torrentID: torrentID, file: file),
                           server: server.absoluteString, torrentID: torrentID, file: file,
                           title: title, source: source, artwork: artwork, seconds: seconds, duration: duration,
                           updatedAt: Date(timeIntervalSince1970: updatedAt))
    }
}
private struct RemoteResumeList: Decodable { let items: [RemoteResume] }
private struct ResumeUpload: Encodable { let items: [RemoteResume]; let clearBefore: Double? }
private struct PendingResume: Codable { let server: String; let change: RemoteResume }

@MainActor @Observable
final class ResumeHistory {
    private(set) var entries: [ResumeEntry]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: [String: PendingResume]
    @ObservationIgnored private var pendingClears: [String: Double]
    @ObservationIgnored private var api: TorrentTubeAPI?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncAgain = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        entries = defaults.data(forKey: "resumeHistory").flatMap { try? decoder.decode([ResumeEntry].self, from: $0) } ?? []
        pending = defaults.data(forKey: "resumeHistory.pending").flatMap { try? decoder.decode([String: PendingResume].self, from: $0) } ?? [:]
        pendingClears = defaults.data(forKey: "resumeHistory.clears").flatMap { try? decoder.decode([String: Double].self, from: $0) } ?? [:]
        if !defaults.bool(forKey: "resumeHistory.serverMigrated") {
            for entry in entries { pending[entry.id] = PendingResume(server: entry.server, change: RemoteResume(entry)) }
            defaults.set(true, forKey: "resumeHistory.serverMigrated")
            persist()
        }
        // Enable on existing installs once, then keep later user choices.
        if !defaults.bool(forKey: "continueWatching.defaultEnabled") {
            defaults.set(true, forKey: "showContinueWatching")
            defaults.set(true, forKey: "continueWatching.defaultEnabled")
        }
    }
    nonisolated static func key(server: URL, torrentID: String, file: Int) -> String {
        "\(server.absoluteString)|\(torrentID)|\(file)"
    }
    func entry(server: URL, torrentID: String, file: Int) -> ResumeEntry? {
        entries.first { $0.id == Self.key(server: server, torrentID: torrentID, file: file) }
    }
    func clear(server: URL) {
        let address = server.absoluteString
        pendingClears[address] = Date().timeIntervalSince1970
        pending = pending.filter { $0.value.server != address }
        entries.removeAll { $0.server == address }
        persist()
        if api?.baseURL == server { sync() }
    }
    func save(server: URL, session: PlaybackSession, title: String, source: PlaybackSource, seconds: Double, duration: Double, artwork: String? = nil, completed: Bool = false) {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let key = Self.key(server: server, torrentID: session.id, file: session.file)
        let removed = completed || seconds < 10 || seconds >= duration - 15
        var selected = source
        selected.file = session.file
        let entry = ResumeEntry(id: key, server: server.absoluteString, torrentID: session.id, file: session.file,
                                title: title, source: selected, artwork: artwork, seconds: seconds, duration: duration, updatedAt: Date())
        entries.removeAll { $0.id == key }
        if !removed { entries.insert(entry, at: 0) }
        // Limit each server separately, so a second server does not erase the first.
        var counts: [String: Int] = [:]
        entries = entries.filter { counts[$0.server, default: 0] += 1; return counts[$0.server, default: 0] <= 50 }
        pending[key] = PendingResume(server: server.absoluteString, change: RemoteResume(entry, removed: removed))
        persist()
        if api?.baseURL == server { sync() }
    }
    func connect(_ api: TorrentTubeAPI, config: ServerConfig) {
        self.api = config.capabilities?.continueWatching == true ? api : nil
        sync()
    }
    /// One request at a time; offline changes remain queued across app restarts.
    @discardableResult func sync() -> Task<Void, Never> {
        if let syncTask { syncAgain = true; return syncTask }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.syncAgain = false
                let succeeded = await self.performSync()
                if !succeeded { break }
            } while self.syncAgain && !Task.isCancelled
            self.syncTask = nil
        }
        syncTask = task
        return task
    }
    private func performSync() async -> Bool {
        guard let api else { return false }
        let address = api.baseURL.absoluteString
        let changes = pending.filter { $0.value.server == address }
        let clear = pendingClears[address]
        do {
            let list: RemoteResumeList
            if !changes.isEmpty || clear != nil {
                list = try await api.post("api/continue-watching", body: ResumeUpload(items: changes.values.map(\.change), clearBefore: clear))
                for (key, sent) in changes where pending[key]?.change == sent.change { pending.removeValue(forKey: key) }
                if pendingClears[address] == clear { pendingClears.removeValue(forKey: address) }
            } else {
                list = try await api.request("api/continue-watching")
            }
            // Preserve writes made during the request. The next pass sends them.
            let local = entries.filter { $0.server == address && pending[$0.id] != nil }
            let remote = list.items.compactMap { $0.local(server: api.baseURL) }.filter {
                pending[$0.id] == nil && $0.updatedAt.timeIntervalSince1970 > (pendingClears[address] ?? 0)
            }
            entries = entries.filter { $0.server != address } + (local + remote).sorted { $0.updatedAt > $1.updatedAt }
            persist()
            return true
        } catch {
            persist()
            return false
        }
    }
    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(entries) { defaults.set(data, forKey: "resumeHistory") }
        if let data = try? encoder.encode(pending) { defaults.set(data, forKey: "resumeHistory.pending") }
        if let data = try? encoder.encode(pendingClears) { defaults.set(data, forKey: "resumeHistory.clears") }
    }
}
