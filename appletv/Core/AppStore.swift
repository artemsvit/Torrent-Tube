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
    var error: String?
    var address = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    private var connectionID = UUID()

    func connect() async {
        let operation = UUID()
        connectionID = operation
        connecting = true
        error = nil
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
            if connectionID == operation { self.error = error.localizedDescription }
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
        error = nil
    }
}

