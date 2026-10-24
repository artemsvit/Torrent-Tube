import Foundation
import Observation
#if os(tvOS)
import TVServices
#endif

@MainActor @Observable
final class AppStore {
    var api: TorrentTubeAPI?
    var config: ServerConfig?
    var shelfTitleID: String?
    var connecting = false
    /// What went wrong, in the app's language: a short title and a tip.
    var error: String?
    var errorTip: String?
    var address = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    private var connectionID = UUID()

    func connect() async {
        let operation = UUID()
        connectionID = operation
        connecting = true
        error = nil; errorTip = nil
        defer { if connectionID == operation { connecting = false } }
        do {
            let client = TorrentTubeAPI(baseURL: try TorrentTubeAPI.serverURL(address))
            let result: ServerConfig = try await client.request("api/config")
            guard result.server == nil || result.server == "torrenttube" else {
                throw APIError(message: L("This address belongs to another service."))
            }
            guard result.apiVersion == nil || result.apiVersion == 1 else {
                throw APIError(message: L("This server version is not supported. Update the app."))
            }
            try Task.checkCancellation()
            guard connectionID == operation else { return }
            #if os(tvOS)
            if TopShelfStore.snapshot?.server != client.baseURL.absoluteString {
                TopShelfStore.clear()
                TVTopShelfContentProvider.topShelfContentDidChange()
            }
            TopShelfStore.defaults.set(client.baseURL.absoluteString, forKey: "activeServer")
            #endif
            config = result
            if let language = result.audioLanguage { AudioSettings.language = language }
            api = client
            address = client.baseURL.absoluteString
            UserDefaults.standard.set(address, forKey: "serverAddress")
        } catch is CancellationError {} catch {
            if connectionID == operation { (self.error, errorTip) = Self.describe(error) }
        }
    }

    /// System network errors arrive in English; say them in the app's
    /// language, with what to check.
    static func describe(_ error: Error) -> (String, String?) {
        if let api = error as? APIError { return (api.message, nil) }
        guard let url = error as? URLError else { return (L("Couldn’t connect to the server"), error.localizedDescription) }
        switch url.code {
        case .timedOut:
            return (L("The server is not responding"), L("Check that the server is on and this device is on the same Wi-Fi network."))
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return (L("No network connection"), L("Connect to the same Wi-Fi network as your server."))
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return (L("Can’t reach this address"), L("Check the address and port, for example http://192.168.0.102:5058."))
        case .badURL, .unsupportedURL:
            return (L("This address is not valid"), L("Use an address like http://192.168.0.102:5058."))
        default:
            return (L("Couldn’t connect to the server"), L("Check that the server is on and this device is on the same Wi-Fi network."))
        }
    }

    /// At launch: a failure within a few seconds is retried - right after the
    /// app starts, macOS can refuse the first local-network request while it
    /// checks the app's Local Network access. A real timeout is not retried.
    func connectAtLaunch() async {
        for attempt in 0..<3 {
            let started = Date()
            await connect()
            guard api == nil, error != nil, attempt < 2, Date().timeIntervalSince(started) < 3 else { return }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    func disconnect() {
        #if os(tvOS)
        TopShelfStore.defaults.removeObject(forKey: "activeServer")
        TopShelfStore.clear()
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
        connectionID = UUID()
        api = nil
        config = nil
        connecting = false
        error = nil; errorTip = nil
    }
}


/// The server's Library settings (Download new episodes, Default audio
/// track) for a Settings screen: loaded when it opens, saved on each change.
@MainActor @Observable
final class LibrarySettingsStore {
    var settings: LibrarySettings?
    var saving = false
    var error: String?

    func load(api: TorrentTubeAPI) async {
        do {
            let loaded: LibrarySettings = try await api.request("api/library/settings")
            settings = loaded
            AudioSettings.language = loaded.audioLanguage
            error = nil
        } catch is CancellationError {} catch { self.error = AppStore.describe(error).0 }
    }

    func save(_ change: LibrarySettingsChange, api: TorrentTubeAPI) async {
        saving = true
        defer { saving = false }
        do {
            let saved: LibrarySettings = try await api.post("api/library/settings", body: change)
            settings = saved
            AudioSettings.language = saved.audioLanguage
            error = nil
        } catch is CancellationError {} catch { self.error = AppStore.describe(error).0 }
    }

    var audioName: String {
        guard let settings else { return "" }
        return settings.audioLanguages.first { $0.code == settings.audioLanguage }?.name ?? settings.audioLanguage
    }
}

/// Fix match: search TMDB for a library title's right film or show (in any
/// language) and save it. The same steps on every device; each draws it its way.
@MainActor @Observable
final class MatchEditor {
    let itemID: String
    var info: MatchInfo?
    var query = ""
    var year = ""
    var type = "movie"
    var language = "uk-UA"
    var results: [MatchCandidate] = []
    var searching = false
    var saving = false
    var error: String?

    init(itemID: String) { self.itemID = itemID }

    func load(api: TorrentTubeAPI) async {
        do {
            let loaded: MatchInfo = try await api.request("api/library/match", query: [.init(name: "id", value: itemID)])
            info = loaded
            query = loaded.query; year = loaded.year ?? ""; type = loaded.type; language = loaded.language
            await search(api: api)
        } catch is CancellationError {} catch { self.error = AppStore.describe(error).0 }
    }

    func search(api: TorrentTubeAPI) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; return }
        searching = true
        defer { searching = false }
        var items: [URLQueryItem] = [.init(name: "q", value: term), .init(name: "type", value: type), .init(name: "language", value: language)]
        let digits = year.filter(\.isNumber)
        if digits.count == 4 { items.append(.init(name: "year", value: digits)) }
        do {
            let found: MatchSearchResponse = try await api.request("api/library/match/search", query: items)
            results = found.results
            error = nil
        } catch is CancellationError {} catch { self.error = AppStore.describe(error).0 }
    }

    /// Saves the match, then reloads the library and the title's details.
    func save(_ candidate: MatchCandidate, api: TorrentTubeAPI, catalog: CatalogStore) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            let change = MatchChange(id: itemID, tmdbId: candidate.tmdbId, mediaType: candidate.mediaType ?? type, language: language)
            let _: Saved = try await api.post("api/library/match", body: change)
            await catalog.loadLibrary(api: api)
            return true
        } catch is CancellationError { return false } catch { self.error = AppStore.describe(error).0; return false }
    }

    /// Forgets the hand-picked match: the server matches the title again.
    func reset(api: TorrentTubeAPI, catalog: CatalogStore) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let _: Saved = try await api.request("api/library/match", method: "DELETE", body: try encoder.encode(MatchReset(id: itemID)))
            await catalog.loadLibrary(api: api)
            return true
        } catch is CancellationError { return false } catch { self.error = AppStore.describe(error).0; return false }
    }
    private struct Saved: Decodable { let ok: Bool }

    /// "Українська", "English": a TMDB language in the app's language.
    static func languageName(_ code: String) -> String {
        let name = Localizer.shared.language.locale.localizedString(forLanguageCode: String(code.prefix(2))) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
