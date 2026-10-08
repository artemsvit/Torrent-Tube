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

@MainActor @Observable
final class ResumeHistory {
    private(set) var entries: [ResumeEntry]
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: "resumeHistory").flatMap { try? JSONDecoder().decode([ResumeEntry].self, from: $0) } ?? []
    }
    static func key(server: URL, torrentID: String, file: Int) -> String {
        "\(server.absoluteString)|\(torrentID)|\(file)"
    }
    func entry(server: URL, torrentID: String, file: Int) -> ResumeEntry? {
        entries.first { $0.id == Self.key(server: server, torrentID: torrentID, file: file) }
    }
    func clear(server: URL) {
        entries.removeAll { $0.server == server.absoluteString }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "resumeHistory") }
    }
    func save(server: URL, session: PlaybackSession, title: String, source: PlaybackSource, seconds: Double, duration: Double, artwork: String? = nil, completed: Bool = false) {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let key = Self.key(server: server, torrentID: session.id, file: session.file)
        entries.removeAll { $0.id == key }
        if !completed && seconds >= 10 && seconds < duration - 15 {
            var selected = source
            selected.file = session.file
            entries.insert(.init(id: key, server: server.absoluteString, torrentID: session.id, file: session.file, title: title, source: selected, artwork: artwork, seconds: seconds, duration: duration, updatedAt: Date()), at: 0)
        }
        entries = Array(entries.prefix(50))
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "resumeHistory") }
    }
}
