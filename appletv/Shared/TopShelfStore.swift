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
    static var snapshot: ShelfSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ShelfSnapshot.self, from: data)
    }
    static func save(_ snapshot: ShelfSnapshot) {
        guard let file, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }
    static func clear() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
