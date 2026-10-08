import SwiftUI
import Observation
import UIKit
import TVServices

extension Color {
    static let torrentAccent = Color(red: 0.23, green: 0.576, blue: 1)
}

@main
struct TorrentTubeApp: App {
    @State private var store = AppStore()
    @State private var history = ResumeHistory()
    @State private var favorites = FavoritesStore()
    @State private var didAttemptReconnect = false
    @State private var localizer = Localizer.shared
    init() {
        let appearance = UITabBar.appearance().standardAppearance.copy()
        for items in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            items.focused.iconColor = .black
            items.focused.titleTextAttributes[.foregroundColor] = UIColor.black
        }
        UITabBar.appearance().standardAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let api = store.api, let config = store.config {
                    MainView(store: store, api: api, config: config)
                } else {
                    ConnectionView(store: store)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "torrenttube", url.host == "title" else { return }
                store.shelfTitleID = url.lastPathComponent
            }
            .environment(history)
            .environment(favorites)
            .environment(\.locale, localizer.language.locale)
            .tint(Color.torrentAccent)
            .preferredColorScheme(.dark)
            .task {
                guard !didAttemptReconnect else { return }
                didAttemptReconnect = true
                if store.api == nil && !store.address.isEmpty { await store.connect() }
            }
        }
    }
}

struct ConnectionView: View {
    @Bindable var store: AppStore
    @FocusState private var field: Field?
    private enum Field { case address, connect }
    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "play.fill").font(.system(size: 65, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 110, height: 110).background(Color.torrentAccent, in: RoundedRectangle(cornerRadius: 26))
            Text("Torrent Tube").font(.largeTitle.bold())
            Text(L("Connect to your server")).font(.title2)
            TextField(L("Server address"), text: $store.address)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($field, equals: .address)
                .accessibilityIdentifier("server-address")
                .onSubmit { Task { await store.connect() } }
            Text(L("Example: %@", "http://192.168.0.102:5058")).font(.callout).foregroundStyle(.secondary)
            if store.connecting { ProgressView(L("Connecting…")) }
            if let error = store.error { Text(error).foregroundStyle(.orange).multilineTextAlignment(.center) }
            Button(L("Connect")) { Task { await store.connect() } }
                .focused($field, equals: .connect)
                .disabled(store.connecting || store.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("connect")
        }
        .frame(maxWidth: 780)
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.065, blue: 0.08))
        .defaultFocus($field, .address)
    }
}
