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

