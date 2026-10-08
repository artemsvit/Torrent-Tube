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

    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { content().macCover() }
    }
    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                            @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { content($0).macCover() }
    }
    fileprivate func macCover() -> some View {
        frame(minWidth: 900, idealWidth: 1280, minHeight: 560, idealHeight: 780)
    }
}
#endif

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
