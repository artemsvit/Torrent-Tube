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
        // Posters, backdrops and cast photos stay on the device between launches
        // (tvOS keeps it in Caches, which the system may clear when space runs low).
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
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

/// The welcome screen: the brand on a glowing backdrop and one glass card
/// with the server address - the same design on Apple TV, iPad and iPhone.
struct ConnectionView: View {
    @Bindable var store: AppStore
    @FocusState private var field: Field?
    private enum Field { case address, connect }
    private var canConnect: Bool { !store.connecting && !store.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 44) {
                VStack(spacing: 22) {
                    BrandMark(size: 140)
                    Text("Torrent Tube").font(.system(size: 66, weight: .heavy))
                    Text(L("Enter the address of your Torrent Tube server."))
                        .font(.system(size: 30)).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Label(L("Server address"), systemImage: "server.rack")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    TextField("http://192.168.0.102:5058", text: $store.address)
                        .font(.system(size: 30))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($field, equals: .address)
                        .accessibilityIdentifier("server-address")
                        .onSubmit { Task { await store.connect() } }
                    Text(L("Example: %@", "http://192.168.0.102:5058")).font(.system(size: 22)).foregroundStyle(.white.opacity(0.45))
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 24)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { Task { await store.connect() } } label: {
                        HStack(spacing: 16) {
                            if store.connecting { ProgressView().tint(.black) }
                            Text(store.connecting ? L("Connecting…") : L("Connect")).font(.system(size: 30, weight: .semibold))
                            if !store.connecting { Image(systemName: "arrow.right").font(.system(size: 26, weight: .semibold)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .focused($field, equals: .connect)
                    .disabled(!canConnect)
                    .opacity(canConnect || store.connecting ? 1 : 0.45)
                    .accessibilityIdentifier("connect")
                    .padding(.top, 10)
                }
                .padding(44)
                .frame(width: 900)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .focusSection()
                Label(L("The server and this device must be on the same network."), systemImage: "wifi")
                    .font(.system(size: 22)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(60)
        }
        .defaultFocus($field, .address)
    }
}
