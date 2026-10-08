import Foundation

enum TrailerChoice {
    static func pick(_ trailers: [Trailer]) -> Trailer? {
        let valid = trailers.filter(\.isValid)
        return valid.first { $0.lang?.lowercased().hasPrefix("en") == true } ?? valid.first
    }
    static func find(title: String, year: String?, known: [Trailer], api: TorrentTubeAPI) async throws -> Trailer? {
        if let trailer = pick(known) { return trailer }
        var query = [URLQueryItem(name: "title", value: title)]
        if let year, !year.isEmpty { query.append(.init(name: "year", value: year)) }
        let result: TrailerResponse = try await api.request("api/trailer", query: query)
        return pick(result.videos)
    }
}



