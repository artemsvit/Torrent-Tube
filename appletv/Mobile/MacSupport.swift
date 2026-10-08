import SwiftUI
#if os(macOS)
import AppKit

/// The window is all content: no title, no close/minimise/zoom buttons
/// (⌘W closes it, ⌃⌘F fills the screen). The top row drags it.
struct BarelessWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Finder() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Finder: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.backgroundColor = .black
        }
    }
}

/// The Mac top row: one height for every control in it.
enum MacBar {
    static let height: CGFloat = 70
    static let control: CGFloat = 46
}

/// The always-visible search field at the right of the Mac top row (⌘F).
struct MacSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            TextField(L("Search"), text: $text)
                .textFieldStyle(.plain).font(.system(size: 16))
                .focused(focused)
                .onExitCommand { text = ""; focused.wrappedValue = false }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6)) }
                    .buttonStyle(.plain).help(L("Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: MacBar.control)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(focused.wrappedValue ? 0.35 : 0.1)))
        .background { Button("") { focused.wrappedValue = true }.keyboardShortcut("f", modifiers: .command).hidden() }
    }
}

/// A round glass button in the Mac top row.
struct MacBarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: MacBar.control, height: MacBar.control)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// The iPhone/iPad screens also build the Mac app. These stand in for the
/// few iOS-only modifiers: phone details (status bar, keyboard) do nothing,
/// and full-screen covers open as large sheets over the window.
enum TitleDisplayMode { case automatic, inline, large }
struct TextAutocapitalization { static let never = Self(), words = Self(), sentences = Self() }
struct KeyboardKind { static let URL = Self(), webSearch = Self(), numberPad = Self(), `default` = Self() }

extension View {
    func navigationBarTitleDisplayMode(_ mode: TitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ value: TextAutocapitalization?) -> some View { self }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }
    func keyboardType(_ kind: KeyboardKind) -> some View { self }

    /// On the Mac a full-screen cover (the player, a trailer) fills the whole
    /// window, over the top row too - shown by the window's MacCoverHost.
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(MacCover(shown: isPresented.wrappedValue, key: "cover", close: { isPresented.wrappedValue = false },
                          onDismiss: onDismiss, cover: { AnyView(content()) }))
    }
    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                            @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(MacCover(shown: item.wrappedValue != nil, key: item.wrappedValue.map { "\($0.id)" } ?? "", close: { item.wrappedValue = nil },
                          onDismiss: onDismiss, cover: { item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView()) }))
    }
}

/// The one cover the Mac window shows at a time.
@MainActor @Observable final class MacCovers {
    var current: AnyView?
    var owner: UUID?
    var close: (() -> Void)?
}

private struct MacCover: ViewModifier {
    let shown: Bool
    let key: String
    let close: () -> Void
    let onDismiss: (() -> Void)?
    let cover: () -> AnyView
    @Environment(MacCovers.self) private var covers
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .onChange(of: "\(shown)|\(key)", initial: true) { _, _ in
                if shown {
                    covers.current = cover(); covers.owner = id; covers.close = close
                } else if covers.owner == id {
                    covers.current = nil; covers.owner = nil; covers.close = nil
                    onDismiss?()
                }
            }
            .onDisappear { if covers.owner == id { covers.current = nil; covers.owner = nil; covers.close = nil } }
    }
}

/// Shows the current cover over the whole window; Esc closes it.
struct MacCoverHost: ViewModifier {
    @Environment(MacCovers.self) private var covers
    func body(content: Content) -> some View {
        content.overlay {
            if let cover = covers.current {
                cover
                    .environment(\.closeCover) { covers.close?() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .onExitCommand { covers.close?() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: covers.owner)
    }
}
#endif

/// The Mac's way to close a full-window cover; nil elsewhere (the system's dismiss is used).
private struct CloseCoverKey: EnvironmentKey { static let defaultValue: (@MainActor () -> Void)? = nil }
extension EnvironmentValues {
    var closeCover: (@MainActor () -> Void)? {
        get { self[CloseCoverKey.self] }
        set { self[CloseCoverKey.self] = newValue }
    }
}

extension View {
    /// The Search screen has its own field and close button.
    func hidesNavigationBar() -> some View {
        #if os(macOS)
        self
        #else
        toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Top left and top right of the bar (on the Mac: the window toolbar).
    static var leadingBar: Self {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }
    static var trailingBar: Self {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}

enum DeviceKind {
    /// iPad and Mac: room for the wide layouts.
    @MainActor static var isLargeScreen: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

extension View {
    /// The white Play button. macOS greys out prominent buttons while the
    /// window is inactive, so the Mac draws its own white pill.
    @ViewBuilder func primaryHeroButton() -> some View {
        #if os(macOS)
        buttonStyle(MacPrimaryStyle())
        #else
        buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
        #endif
    }
}

#if os(macOS)
private struct MacPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .background(.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}
#endif

/// Keeps the screen awake while a video plays.
enum ScreenSleep {
    #if os(macOS)
    private static var activity: NSObjectProtocol?
    #endif
    @MainActor static func prevent(_ prevent: Bool) {
        #if os(macOS)
        if prevent, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing video")
        } else if !prevent, let current = activity {
            ProcessInfo.processInfo.endActivity(current); activity = nil
        }
        #else
        UIApplication.shared.isIdleTimerDisabled = prevent
        #endif
    }

    /// Where the user allows Local Network access.
    @MainActor static func openNetworkSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") { NSWorkspace.shared.open(url) }
        #else
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        #endif
    }
}
