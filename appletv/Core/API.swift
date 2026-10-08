import Foundation

struct ServerConfig: Decodable {
    let categories: [String]
    let searchEnabled: Bool
    let tmdbEnabled: Bool
    let server: String?
    let apiVersion: Int?
    let capabilities: Capabilities?
    struct Capabilities: Decodable {
        let fileSelection: Bool?
        let playbackSessions: Bool?
        var topShelfPreviews: Bool? = nil
    }
    var supportsPlayback: Bool { capabilities?.playbackSessions == true && capabilities?.fileSelection == true }
}

struct Feed: Decodable, Identifiable { let id: String; let label: String }
struct FeedResponse: Decodable { let feeds: [Feed] }
struct CatalogResponse: Codable { let results: [MediaItem] }
struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    let title: String
    var cleanTitle: String?
    var poster: String?
    var rating: Double?
    var overview: String?
    var tmdbId: Int?
    var mediaType: String?
    let magnet: String?
    let downloadLink: String?
    let sizeLabel: String?
    let seeders: Int?
    let releases: [Release]?
    var sourceOverride: PlaybackSource? = nil
    var id: String { sourceOverride?.id ?? sourceOverride?.path ?? downloadLink ?? magnet ?? title }
    var displayTitle: String { cleanTitle ?? title }
    var source: PlaybackSource { sourceOverride ?? PlaybackSource(magnet: magnet, downloadLink: downloadLink) }
}
struct Release: Codable, Identifiable, Hashable, Sendable {
    let title: String
    let magnet: String?
    let downloadLink: String?
    let sizeLabel: String?
    let seeders: Int?
    /// A copy already on the server (a Library title saved in two places).
    var path: String? = nil
    var id: String { path ?? downloadLink ?? magnet ?? title }
    var source: PlaybackSource { path.map { PlaybackSource(path: $0) } ?? PlaybackSource(magnet: magnet, downloadLink: downloadLink) }
}
struct Metadata: Codable, Sendable {
    let poster: String?
    let rating: Double?
    let overview: String?
    let cleanTitle: String?
    let tmdbId: Int?
    let mediaType: String?
}
struct Details: Codable, Sendable {
    let title: String?
    let overview: String?
    let backdrop: String?
    let year: String?
    let runtime: Int?
    let tmdbId: Int?
    let mediaType: String?
    let genres: [String]?
    let seasonList: [Season]?
    let trailers: [Trailer]?
    // The rest of what /api/details sends (the web app shows it all).
    let tagline: String?
    /// "Cartoon", "Movie" or "TV show" - the server marks animation as Cartoon.
    let kind: String?
    let originalTitle: String?
    let certification: String?
    let countries: [String]?
    let facts: [Fact]?
    let people: [Person]?
    let recommendations: [Recommendation]?
    struct Fact: Codable, Hashable, Sendable { let label: String; let names: [String] }
    /// A lead (director, creator) or a cast member; role is the job or character.
    struct Person: Codable, Hashable, Sendable { let name: String; let role: String?; let photo: String? }
    struct Recommendation: Codable, Hashable, Sendable {
        let tmdbId: Int?
        let mediaType: String?
        let title: String
        let year: String?
        let poster: String?
    }
    struct Season: Codable, Identifiable, Sendable {
        let number: Int
        let name: String
        let episodes: Int?
        var id: Int { number }
    }
}
struct Trailer: Codable, Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let lang: String?
    var id: String { key }
    var isValid: Bool { key.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil }
    var watchURL: URL? { isValid ? URL(string: "https://www.youtube.com/watch?v=\(key)") : nil }
    var thumbnailURL: String? { isValid ? "https://i.ytimg.com/vi/\(key)/hqdefault.jpg" : nil }
}
struct TrailerResponse: Decodable { let videos: [Trailer] }
struct TrailerStreamResponse: Decodable {
    let url: String; let audioUrl: String?; let subtitleUrl: String?
    /// "uk" or "en" - which language the server found subtitles in.
    var subtitleLanguage: String? = nil
    /// The subtitle track's name in the player menu.
    var subtitleName: String? {
        switch subtitleLanguage { case "uk": "Українська"; case "en": "English"; default: subtitleLanguage }
    }
}

/// Finished torrents - the library of servers without /api/library.
struct TorrentListResponse: Decodable { let torrents: [TorrentListEntry] }
struct TorrentListEntry: Decodable {
    let id: String
    let name: String
    let progress: Double
    let hasMetadata: Bool
}
/// One title already on the server: a film file or a show's folder in the
/// category folders (or, on older servers, a finished torrent).
/// One copy of a Library title: the same film in two folders, or a show split over two.
struct LibraryVersion: Codable, Hashable, Sendable {
    let id: String
    let name: String
    var files: Int = 1
    var size: Int64 = 0
    var category: String = ""
}
struct LibraryTitle: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// The name cleaned of release tags ("Yogi Bear"), shown until - or
    /// without - a TMDB match.
    var title: String? = nil
    var year: String? = nil
    /// "movie", "tv" or "cartoon" - from the folder it is in.
    var kind: String = "movie"
    var files: Int = 1
    /// When it arrived on the server (seconds since 1970).
    var added: Double = 0
    var isTorrent = false
    /// The server's TMDB match for it (newer servers), so the apps need not look it up.
    var displayTitle: String? = nil
    var poster: String? = nil
    var rating: Double? = nil
    var overview: String? = nil
    var tmdbId: Int? = nil
    var mediaType: String? = nil
    /// Every copy on the server when there is more than one; the first plays by default.
    var versions: [LibraryVersion] = []
    var source: PlaybackSource { isTorrent ? PlaybackSource(id: id) : PlaybackSource(path: id) }
    private enum CodingKeys: String, CodingKey { case id, name, title, year, kind, files, added, displayTitle, poster, rating, overview, tmdbId, mediaType, versions, isTorrent }
    init(id: String, name: String, kind: String = "movie", files: Int = 1, added: Double = 0, isTorrent: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.files = files; self.added = added; self.isTorrent = isTorrent
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        year = try c.decodeIfPresent(String.self, forKey: .year)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "movie"
        files = try c.decodeIfPresent(Int.self, forKey: .files) ?? 1
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        tmdbId = try c.decodeIfPresent(Int.self, forKey: .tmdbId)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        added = try c.decodeIfPresent(Double.self, forKey: .added) ?? 0
        versions = try c.decodeIfPresent([LibraryVersion].self, forKey: .versions) ?? []
        isTorrent = try c.decodeIfPresent(Bool.self, forKey: .isTorrent) ?? false
    }
    /// Saved on the device (the Library opens before the server answers).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encodeIfPresent(title, forKey: .title); try c.encodeIfPresent(year, forKey: .year)
        try c.encode(kind, forKey: .kind); try c.encode(files, forKey: .files); try c.encode(added, forKey: .added)
        try c.encodeIfPresent(displayTitle, forKey: .displayTitle); try c.encodeIfPresent(poster, forKey: .poster)
        try c.encodeIfPresent(rating, forKey: .rating); try c.encodeIfPresent(overview, forKey: .overview)
        try c.encodeIfPresent(tmdbId, forKey: .tmdbId); try c.encodeIfPresent(mediaType, forKey: .mediaType)
        try c.encode(versions, forKey: .versions); try c.encode(isTorrent, forKey: .isTorrent)
    }
}
struct LibraryResponse: Decodable {
    let items: [LibraryTitle]
    /// Titles the server is still matching on TMDB (nil on older servers).
    var metadataPending: Int? = nil
}
struct Episode: Decodable, Identifiable {
    let number: Int
    let name: String
    let overview: String?
    let still: String?
    let runtime: Int?
    var id: Int { number }
}
struct EpisodeResponse: Decodable { let episodes: [Episode] }

struct PlaybackSource: Codable, Hashable, Sendable {
    var id: String? = nil
    /// A file or folder already in the server's library - played from disk.
    var path: String? = nil
    var magnet: String? = nil
    var downloadLink: String? = nil
    var file: Int? = nil
    /// Something the server can open: a download, a torrent link or a library path.
    var isPlayable: Bool { id != nil || path != nil || magnet != nil || downloadLink != nil }
}
struct VideoFile: Decodable, Identifiable {
    let index: Int
    let name: String
    let size: Int64
    var path: String? = nil
    var id: Int { index }
    var episodeIdentity: EpisodeIdentity? { EpisodeIdentity.parse(name: name, path: path) }
}
/// Skip intro: where a library episode's opening is ("pending" while the
/// server compares its sound with the next episode).
struct IntroResponse: Decodable { let status: String; let start: Double?; let end: Double? }
struct PreparedPlayback: Decodable { let id: String; let selected: Int; let files: [VideoFile] }
struct PlaybackSession: Decodable {
    let session: String
    let id: String
    let file: Int
    let name: String
    let url: String
    let heartbeatInterval: Int
}
struct StreamStatus: Decodable {
    let ready: Bool
    let headProgress: Double?
    let progress: Double
    let numPeers: Int?
    let gone: Bool?
}
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct TorrentTubeAPI: Sendable {
    let baseURL: URL
    var session: URLSession = .shared

    static func serverURL(_ address: String) throws -> URL {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError(message: L("Enter your server address.")) }
        let text = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard var parts = URLComponents(string: text), let host = parts.host, !host.isEmpty,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw APIError(message: L("Enter an HTTP or HTTPS server address, including its port if needed."))
        }
        parts.scheme = parts.scheme?.lowercased()
        if parts.path.isEmpty { parts.path = "/" }
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        guard let url = parts.url else { throw APIError(message: L("This server address is invalid.")) }
        return url
    }

    func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        let result = path.split(separator: "/").reduce(baseURL) { $0.appendingPathComponent(String($1)) }
        guard var parts = URLComponents(url: result, resolvingAgainstBaseURL: false) else {
            throw APIError(message: L("Could not create the server URL."))
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw APIError(message: L("Could not create the server URL.")) }
        return url
    }

    func mediaURL(_ path: String) throws -> URL {
        // Server paths are already percent-encoded. Keep the configured proxy prefix.
        guard let url = URL(string: String(path.drop(while: { $0 == "/" })), relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host, url.scheme == baseURL.scheme, url.port == baseURL.port,
              url.path.hasPrefix(baseURL.path) else {
            throw APIError(message: L("The server returned an invalid playback URL."))
        }
        return url
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
                                query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = (path.hasPrefix("api/playback") || path == "api/trailer/stream") ? 75 : 40
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        #if os(tvOS)
        let platform = "tvos"
        #else
        let platform = "ios"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        request.setValue(platform, forHTTPHeaderField: "X-TorrentTube-Client")
        request.setValue("TorrentTube-\(platform)/\(version)", forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        // A stopped request (season switched, page closed) is not an error to show.
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw APIError(message: L("No response from the server.")) }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError(message: L("This server requires authentication. This version supports direct LAN connections."))
        }
        if http.statusCode == 404 && path == "api/trailer/stream" {
            throw APIError(message: L("Update Torrent Tube on your server to play trailers inside the app."))
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(message: message ?? L("Server request failed (HTTP %ld).", http.statusCode))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError(message: L("The server returned an unexpected response. Check the address and server version.")) }
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try await request(path, method: "POST", body: encoder.encode(body))
    }
    func command(_ path: String, method: String = "POST") async throws {
        let _: Acknowledgement = try await request(path, method: method, body: method == "POST" ? Data("{}".utf8) : nil)
    }
    struct Acknowledgement: Decodable { let ok: Bool }
}
