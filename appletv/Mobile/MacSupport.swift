import SwiftUI
#if os(macOS)
import AppKit

/// One page per physical scroll gesture; its inertial tail never advances again.
struct MacCarouselScrollState {
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var advanced = false
    private var lastEvent: TimeInterval = 0

    mutating func consume(x deltaX: CGFloat, y deltaY: CGFloat, phase: NSEvent.Phase,
                          momentum: NSEvent.Phase, timestamp: TimeInterval) -> (handled: Bool, step: Int?) {
        if !momentum.isEmpty { return (axis == .horizontal, nil) }
        if phase.contains(.began) || phase.contains(.mayBegin) || (phase.isEmpty && timestamp - lastEvent > 0.3) {
            axis = .undecided; x = 0; y = 0; advanced = false
        }
        lastEvent = timestamp
        if phase.contains(.cancelled) { return (axis == .horizontal, nil) }
        x += deltaX; y += deltaY
        if axis == .undecided {
            if abs(x) > 6, abs(x) > abs(y) * 1.5 { axis = .horizontal }
            else if abs(y) > 6, abs(y) > abs(x) * 1.5 { axis = .vertical }
        }
        guard axis == .horizontal else { return (false, nil) }
        guard !advanced, abs(x) >= 48 else { return (true, nil) }
        advanced = true
        return (true, x < 0 ? 1 : -1)
    }
}

/// SwiftUI DragGesture handles a pressed mouse, but trackpad swipes arrive as
/// scroll-wheel events. Observe only the visible hero without covering its buttons.
struct MacCarouselTrackpad: NSViewRepresentable {
    let enabled: Bool
    let changePage: (Int) -> Void
    let trackingChanged: (Bool) -> Void
    @Environment(MacCovers.self) private var covers
    func makeNSView(context: Context) -> TrackpadView { TrackpadView() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TrackpadView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
    func updateNSView(_ view: TrackpadView, context: Context) {
        view.enabled = enabled && covers.current == nil
        view.changePage = changePage
        view.trackingChanged = trackingChanged
        if !view.enabled { view.resetTracking() }
    }
    static func dismantleNSView(_ view: TrackpadView, coordinator: ()) { view.stopMonitoring() }

    final class TrackpadView: NSView {
        var enabled = false
        var changePage: ((Int) -> Void)?
        var trackingChanged: ((Bool) -> Void)?
        private var tracking = false
        private var gestureAccepted = false
        private var lastEvent: TimeInterval = 0
        private var monitor: Any?
        private var scroll = MacCarouselScrollState()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) { self.setTracking(false) }
                guard self.enabled, let window = self.window, window.isKeyWindow,
                      !self.isHiddenOrHasHiddenAncestor else { return event }
                if let eventWindow = event.window, eventWindow !== window { return event }
                let location = event.window == nil ? window.convertPoint(fromScreen: NSEvent.mouseLocation) : event.locationInWindow
                let insideBanner = self.bounds.intersection(self.visibleRect).contains(self.convert(location, from: nil))
                let startsGesture = event.phase.contains(.began) || event.phase.contains(.mayBegin)
                    || (event.phase.isEmpty && event.momentumPhase.isEmpty && event.timestamp - self.lastEvent > 0.3)
                self.lastEvent = event.timestamp
                if startsGesture {
                    self.scroll = MacCarouselScrollState()
                    self.gestureAccepted = insideBanner
                    self.setTracking(insideBanner)
                }
                guard insideBanner, self.gestureAccepted else { return event }
                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
                let result = self.scroll.consume(x: event.scrollingDeltaX * scale, y: event.scrollingDeltaY * scale,
                                                 phase: event.phase, momentum: event.momentumPhase, timestamp: event.timestamp)
                if let step = result.step { self.changePage?(step) }
                return result.handled ? nil : event
            }
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            scroll = MacCarouselScrollState()
            resetTracking()
        }
        private func setTracking(_ value: Bool) {
            guard tracking != value else { return }
            tracking = value
            trackingChanged?(value)
        }
        func resetTracking() {
            gestureAccepted = false
            scroll = MacCarouselScrollState()
            guard tracking else { return }
            tracking = false
            let publish = trackingChanged
            // A representable may be updating or disappearing; publish afterward.
            DispatchQueue.main.async { publish?(false) }
        }
    }
}

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
            // The app never shows a window toolbar (its own top row instead).
            window.toolbar = nil
            guard observers.isEmpty else { return }
            #if DEBUG
            // Screenshots of full screen: -macFullScreen YES
            if UserDefaults.standard.bool(forKey: "macFullScreen") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak window] in window?.toggleFullScreen(nil) }
            }
            #endif
            // Full screen shows the title bar area as a grey strip and pushes the
            // content down: hide it (and the toolbar) there, bring it back after.
            let center = NotificationCenter.default
            observers = [
                // After entering: changing the toolbar while entering cancels full screen.
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { Self.fullScreen(true, window) }
                },
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { Self.fullScreen(false, window) }
                },
            ]
        }
        private var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        @MainActor private static func fullScreen(_ on: Bool, _ window: NSWindow?) {
            guard let window else { return }
            // SwiftUI may add its (hidden) toolbar back; full screen keeps a title
            // bar strip above the content for it, so keep it removed.
            window.toolbar = nil
            // The view holding the title bar (the window buttons' container's container).
            window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = on
            window.titlebarSeparatorStyle = .none
        }
    }
}

/// The Mac top row: one height for every control in it.
enum MacBar {
    static let height: CGFloat = 70
    static let control: CGFloat = 46
    static let searchWidth: CGFloat = 280
    /// Settings and Back with their padding, at the left of the row.
    static let leftWidth: CGFloat = 16 + control + 10 + control
}

/// The always-visible search field at the right of the Mac top row (⌘F).
struct MacSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var width: CGFloat = MacBar.searchWidth
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
        .frame(width: width, height: MacBar.control)
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
        hapticButtonStyle(BorderedProminentButtonStyle()).tint(.white).foregroundStyle(.black)
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

extension View {
    /// Choosing a release: a sheet on iPhone and iPad, the whole window on the Mac.
    @ViewBuilder func versionsPresentation<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?,
                                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            content().frame(maxWidth: 820).frame(maxWidth: .infinity).background(AppBackground())
        }
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}

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
