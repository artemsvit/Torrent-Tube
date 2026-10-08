import Foundation

/// TMDB matches and title details, saved on this device for one server, so
/// the Library shows its posters at once instead of asking again on every
/// launch. A match is kept until refreshed in Settings; a title with no match
/// is asked again after a week; details are renewed after a month.
@MainActor
final class MetadataCache {
    struct Match: Codable { var metadata: Metadata?; var fetched: Date }
    struct SavedDetails: Codable {
        var details: Details; var fetched: Date
        /// Library titles keep their details until a rescan; others are renewed after a month.
        var permanent: Bool? = nil
    }
    struct SavedLibrary: Codable { var titles: [LibraryTitle]; var synced: Date }
    static let missRetry: TimeInterval = 7 * 24 * 3600
    static let detailsLifetime: TimeInterval = 30 * 24 * 3600
    private static let detailsLimit = 600

    private var matches: [String: Match] = [:]
    private var savedDetails: [String: SavedDetails] = [:]
    private let matchesFile: URL?
    private let detailsFile: URL?
    private let libraryFile: URL?
    /// The server's Library as last synced - shown at once on the next launch.
    private(set) var library: SavedLibrary?

    init(server: URL) {
        let name = server.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "server"
        let folder = Self.folder
        // "v2": matches saved before the server weighed year and type are dropped.
        matchesFile = folder?.appendingPathComponent("metadata-v2-\(name).json")
        detailsFile = folder?.appendingPathComponent("details-v2-\(name).json")
        libraryFile = folder?.appendingPathComponent("library-v2-\(name).json")
        for old in ["metadata-\(name).json", "details-\(name).json"] {
            if let file = folder?.appendingPathComponent(old) { try? FileManager.default.removeItem(at: file) }
        }
        let decoder = JSONDecoder()
        if let file = matchesFile, let data = try? Data(contentsOf: file) {
            matches = (try? decoder.decode([String: Match].self, from: data)) ?? [:]
        }
        if let file = detailsFile, let data = try? Data(contentsOf: file) {
            savedDetails = (try? decoder.decode([String: SavedDetails].self, from: data)) ?? [:]
        }
        if let file = libraryFile, let data = try? Data(contentsOf: file) {
            library = try? decoder.decode(SavedLibrary.self, from: data)
        }
    }

    /// tvOS keeps no permanent local files, so there it is the Caches folder.
    private static var folder: URL? {
        #if os(tvOS)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        guard let folder = base?.appendingPathComponent("TorrentTube", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The saved answer for a title, if it is still good: a match, or a recent "no match".
    func match(for title: String) -> Match? {
        guard let match = matches[title] else { return nil }
        if match.metadata == nil && Date().timeIntervalSince(match.fetched) > Self.missRetry { return nil }
        return match
    }
    /// Saves what the server found for `asked` - including the titles it found nothing for.
    func store(_ found: [String: Metadata], asked: [String]) {
        let now = Date()
        for title in asked { matches[title] = Match(metadata: found[title], fetched: now) }
        write(matches, to: matchesFile)
    }

    func details(for title: String) -> Details? {
        guard let saved = savedDetails[title],
              saved.permanent == true || Date().timeIntervalSince(saved.fetched) < Self.detailsLifetime else { return nil }
        return saved.details
    }
    func store(_ details: Details, for title: String, permanent: Bool = false) {
        savedDetails[title] = SavedDetails(details: details, fetched: Date(), permanent: permanent)
        let temporary = savedDetails.filter { $0.value.permanent != true }
        if temporary.count > Self.detailsLimit {  // the oldest catalog details go first; library ones stay
            for (key, _) in temporary.sorted(by: { $0.value.fetched < $1.value.fetched }).prefix(temporary.count - Self.detailsLimit) {
                savedDetails[key] = nil
            }
        }
        write(savedDetails, to: detailsFile)
    }

    func storeLibrary(_ titles: [LibraryTitle]) {
        library = SavedLibrary(titles: titles, synced: Date())
        write(library, to: libraryFile)
    }
    /// Library titles whose details are saved.
    func hasDetails(_ title: String) -> Bool { details(for: title) != nil }

    /// Titles saved with a match, and the space both files take.
    var matchedCount: Int { matches.values.filter { $0.metadata != nil }.count }
    var bytes: Int {
        [matchesFile, detailsFile, libraryFile].compactMap { $0 }
            .compactMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int }.reduce(0, +)
    }
    func clear() {
        matches = [:]; savedDetails = [:]; library = nil
        for file in [matchesFile, detailsFile, libraryFile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: file) }
    }

    private func write<T: Encodable>(_ value: T, to file: URL?) {
        guard let file, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
