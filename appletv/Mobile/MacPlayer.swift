#if os(macOS)
import SwiftUI
import AppKit

/// The Mac player, in the way of QuickTime and the TV app: the video fills
/// the window, a floating glass panel holds the controls, and both hide (with
/// the pointer) when the mouse rests. Space plays or pauses, ← → skip,
/// F fills the screen, Esc closes.
struct MacPlayer: View {
    let controller: EmbeddedPlayer
    let title: String
    let streamStatus: StreamStatus?
    var episodeLabel: String? = nil
    var artwork: String? = nil
    var intro: ClosedRange<Double>? = nil
    let retry: () -> Void
    let close: () -> Void
    @AppStorage("seekInterval") private var skip = 10
    @State private var visible = true
    @State private var activity = Date()
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var overPanel = false
    @FocusState private var focused: Bool

    private var waiting: Bool { controller.buffering && controller.seconds == 0 }
    private var inIntro: Bool {
        guard let intro, controller.failure == nil else { return false }
        return controller.seconds >= intro.lowerBound && controller.seconds < intro.upperBound - 1
    }

    var body: some View {
        ZStack {
            Color.black
            if waiting { MobilePlaybackBackdrop(artwork: artwork) }
            VideoSurface(controller: controller).id(ObjectIdentifier(controller))
                .opacity(waiting ? 0 : 1)
            // Click: play or pause. Double-click: full screen.
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFullScreen() }
                .onTapGesture { controller.toggle(); reveal() }
            if controller.buffering && controller.failure == nil {
                PlaybackBufferingIndicator()
            }
            if let failure = controller.failure { failureCard(failure) }
        }
        .overlay(alignment: .top) {
            if visible {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) { if visible { topBar.transition(.opacity) } }
        .overlay(alignment: .bottom) {
            if visible && controller.failure == nil { panel.padding(.bottom, 28).transition(.opacity) }
        }
        .overlay(alignment: .bottomTrailing) {
            if inIntro {
                Button { controller.seek(to: intro!.upperBound); reveal() } label: {
                    Label(L("Skip Intro"), systemImage: "forward.end.fill")
                        .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 18).frame(height: 40)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
                }
                .buttonStyle(.plain).accessibilityIdentifier("skip-intro")
                .padding(.trailing, 32).padding(.bottom, visible ? 150 : 32)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .animation(.easeInOut(duration: 0.2), value: inIntro)
        .onContinuousHover { phase in if case .active = phase { reveal() } }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { controller.toggle(); reveal(); return .handled }
        .onKeyPress(.leftArrow) { controller.seek(by: -Double(skip)); reveal(); return .handled }
        .onKeyPress(.rightArrow) { controller.seek(by: Double(skip)); reveal(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress("f") { toggleFullScreen(); return .handled }
        .onAppear { focused = true; ScreenSleep.prevent(true) }
        .onDisappear { ScreenSleep.prevent(false); controller.pause(); NSCursor.setHiddenUntilMouseMoves(false) }
        .task(id: activity) {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if controller.playing, !scrubbing, !overPanel {
                visible = false
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            }
            .buttonStyle(.plain).help(L("Close")).accessibilityIdentifier("close-player")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if let episodeLabel { Text(episodeLabel).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)) }
            }
            .shadow(color: .black.opacity(0.5), radius: 6)
        }
        .padding(20)
    }

    private var panel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                trackMenu(subtitles: false)
                Spacer()
                HStack(spacing: 26) {
                    panelButton("gobackward.\(skip)", size: 20, help: L("Back %ld seconds", skip)) { controller.seek(by: -Double(skip)) }
                        .accessibilityIdentifier("seek-backward")
                    panelButton(controller.playing ? "pause.fill" : "play.fill", size: 28, help: L(controller.playing ? "Pause" : "Play")) { controller.toggle() }
                        .accessibilityIdentifier("toggle-playback")
                    panelButton("goforward.\(skip)", size: 20, help: L("Forward %ld seconds", skip)) { controller.seek(by: Double(skip)) }
                        .accessibilityIdentifier("seek-forward")
                }
                Spacer()
                HStack(spacing: 18) {
                    trackMenu(subtitles: true)
                    panelButton("arrow.up.left.and.arrow.down.right", size: 15, help: L("Full Screen")) { toggleFullScreen() }
                }
            }
            HStack(spacing: 12) {
                Text(ResumeEntry.time(scrubbing ? scrub : controller.seconds))
                    .accessibilityIdentifier("playback-position")
                Slider(value: Binding(get: { scrubbing ? scrub : controller.seconds }, set: { scrub = $0 }),
                       in: 0...max(1, controller.duration)) { editing in
                    scrubbing = editing
                    if !editing { controller.seek(to: scrub) }
                    reveal()
                }
                .controlSize(.small).tint(.white)
                .disabled(controller.duration <= 0)
                .accessibilityLabel(L("Playback position")).accessibilityIdentifier("playback-scrubber")
                Text("-" + ResumeEntry.time(max(0, controller.duration - (scrubbing ? scrub : controller.seconds))))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(width: 640)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .onHover { overPanel = $0 }
    }

    private func panelButton(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button { action(); reveal() } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: size + 18, height: size + 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    /// Audio and subtitles as ordinary Mac menus, the chosen track ticked.
    private func trackMenu(subtitles: Bool) -> some View {
        let tracks = subtitles ? controller.subtitleTracks.filter { $0.id >= 0 } : controller.audioTracks
        let current = subtitles ? controller.player.currentVideoSubTitleIndex : controller.player.currentAudioTrackIndex
        return Menu {
            if subtitles {
                Toggle(L("Off"), isOn: Binding(get: { current == -1 }, set: { if $0 { controller.player.currentVideoSubTitleIndex = -1 } }))
            }
            ForEach(tracks) { track in
                Toggle(track.name, isOn: Binding(get: { current == track.id }, set: { on in
                    guard on else { return }
                    if subtitles { controller.player.currentVideoSubTitleIndex = track.id }
                    else { controller.player.currentAudioTrackIndex = track.id }
                }))
            }
            if tracks.isEmpty { Text(L("No tracks available yet.")) }
        } label: {
            Image(systemName: subtitles ? "captions.bubble" : "waveform").font(.system(size: 16, weight: .semibold))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(L(subtitles ? "Subtitles" : "Audio"))
        .accessibilityIdentifier(subtitles ? "subtitle-tracks" : "audio-tracks")
    }

    private func failureCard(_ failure: String) -> some View {
        VStack(spacing: 16) {
            Text(failure).font(.system(size: 15)).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button(L("Close player"), action: close).buttonStyle(.bordered)
                Button(L("Try again"), action: retry).buttonStyle(.borderedProminent)
            }
        }
        .padding(26).frame(maxWidth: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    private func reveal() {
        if !visible { visible = true }
        activity = Date()
    }
}
#endif
