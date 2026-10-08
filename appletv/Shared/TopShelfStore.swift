import Foundation
import CryptoKit

struct ShelfTitle: Codable, Identifiable {
    let id: String
    let title: String
    let rawTitle: String
    let poster: String
    let magnet: String?
    let downloadLink: String?
    let tmdbID: Int?
    let mediaType: String?
    var artworkID: String? = nil
    var backdrop: String? = nil
    var previewURL: String? = nil
    // Shown over the banner: kind (already translated), year, rating, genres, description.
    var kind: String? = nil
    var year: String? = nil
    var rating: Double? = nil
    var genres: [String]? = nil
    var overview: String? = nil

    static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var url: URL { URL(string: "torrenttube://title/\(id)")! }
}

struct ShelfSnapshot: Codable {
    let server: String
    let titles: [ShelfTitle]
}

enum TopShelfStore {
    static let group = "group.com.artsvit.torrenttube.tv"
    static var defaults: UserDefaults { UserDefaults(suiteName: group)! }
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("top-shelf.json")
    }
    static var artworkDirectory: URL? { file?.deletingLastPathComponent().appendingPathComponent("top-shelf-artwork", isDirectory: true) }
    static func artworkURL(for title: ShelfTitle) -> URL? {
        guard let key = title.artworkID, key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let url = artworkDirectory?.appendingPathComponent(key + ".jpg"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    static var snapshot: ShelfSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ShelfSnapshot.self, from: data)
    }
    static func save(_ snapshot: ShelfSnapshot) {
        guard let file, let data = try? JSONEncoder().encode(snapshot) else { return }
        do { try data.write(to: file, options: .atomic) } catch { return }
        // Keep current banners and a bounded set of older images while the system refreshes.
        if let directory = artworkDirectory,
           let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let current = Set(snapshot.titles.compactMap(\.artworkID).map { $0 + ".jpg" })
            let older = files.filter { $0.pathExtension == "jpg" && !current.contains($0.lastPathComponent) }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                          ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for url in older.dropFirst(24) { try? FileManager.default.removeItem(at: url) }
        }
    }
    static func clear() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
