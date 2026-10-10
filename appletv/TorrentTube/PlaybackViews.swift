import SwiftUI
import UIKit

struct PlaybackLauncher: View {
    let request: PlaybackRequest
    let api: TorrentTubeAPI
    @Environment(\.dismiss) private var dismiss
    @Environment(ResumeHistory.self) private var history
    @State private var model: PlaybackCoordinator
    init(request: PlaybackRequest, api: TorrentTubeAPI) {
        self.request = request; self.api = api
        _model = State(initialValue: PlaybackCoordinator(request: request, api: api))
    }

    var body: some View {
        ZStack {
            if let controller = model.controller {
                PlayerView(controller: controller, title: request.title, streamStatus: model.streamStatus, episodeLabel: model.episodeLabel, intro: model.intro) { close() }
                    .id(ObjectIdentifier(controller))

            } else {
                ZStack(alignment: .leading) {
                    ArtworkView(url: request.artwork, background: true, fill: true)
                        .ignoresSafeArea()
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.94), location: 0),
                            .init(color: .black.opacity(0.8), location: 0.45),
                            .init(color: .black.opacity(0.4), location: 0.75),
                            .init(color: .black.opacity(0.85), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .ignoresSafeArea()
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.6), location: 0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.7), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    if let resumeEntry = model.resumeEntry, model.error == nil, !model.loading {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        TVResumePrompt(title: request.title, position: resumeEntry.displayPosition,
                                       resume: { model.openPlayer(at: resumeEntry.seconds) },
                                       restart: { model.openPlayer(at: 0) }, back: close)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 32) {
                                Text(request.title)
                                    .font(.system(size: 64, weight: .heavy))
                                    .lineLimit(2)
                                    .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

                                if let error = model.error {
                                    VStack(alignment: .leading, spacing: 24) {
                                        HStack(spacing: 16) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 28, weight: .bold))
                                                .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.2))
                                            Text(error)
                                                .font(.system(size: 30, weight: .medium))
                                                .foregroundStyle(.white)
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 16)
                                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                        )

                                        HStack(spacing: 24) {
                                            Button {
                                                Task { await model.prepare() }
                                            } label: {
                                                Label(L("Try again"), systemImage: "arrow.clockwise")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.white)
                                            .foregroundStyle(.black)

                                            Button(action: close) {
                                                Label(L("Back"), systemImage: "arrow.backward")
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(.white.opacity(0.25))
                                            .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(.top, 8)
                                    .focusSection()
                                } else if let prepared = model.prepared, !model.loading {
                                    Text(request.episode.map { L("Choose a file for episode %ld", $0) } ?? L("Choose an episode"))
                                        .font(.system(size: 32, weight: .semibold))
                                    ScrollView(.horizontal) {
                                        LazyHStack(alignment: .top, spacing: 32) {
                                            ForEach(prepared.files) { file in
                                                let identity = file.episodeIdentity
                                                let episode = identity.flatMap { identity in model.episodeMetadata[identity.season]?.first { $0.number == identity.episode } }
                                                Button { Task { await model.start(file: file.index) } } label: {
                                                    VStack(alignment: .leading, spacing: 16) {
                                                        ArtworkView(url: episode?.still ?? request.artwork).frame(width: 380, height: 214).clipShape(RoundedRectangle(cornerRadius: 12))
                                                        Text(episode.map { "\($0.number). \($0.name)" } ?? file.name).font(.system(size: 26, weight: .semibold)).lineLimit(2)
                                                        if let identity { Text(identity.label).font(.system(size: 22)).foregroundStyle(.secondary) }
                                                    }.frame(width: 380, alignment: .leading)
                                                }.buttonStyle(CinemaCardStyle())
                                            }
                                        }.padding(.vertical, 18).padding(.horizontal, 12)
                                    }.focusSection()

                                    Button(action: close) {
                                        Label(L("Back"), systemImage: "arrow.backward")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.white.opacity(0.25))
                                    .foregroundStyle(.white)
                                    .padding(.top, 8)
                                }
                            }
                            .padding(.horizontal, 90)
                            .padding(.vertical, 80)
                        }
                    }

                    if model.loading {
                        ZStack {
                            Color.black.opacity(0.55).ignoresSafeArea()
                            VStack(spacing: 24) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(1.4)
                                Text(L("Preparing your stream…"))
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .padding(40)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                        }
                        .ignoresSafeArea()
                    }
                }
                .background(.black)
                .ignoresSafeArea()
            }
        }
        .task { model.history = history; await model.prepare() }
        .task(id: model.prepared?.id) { await model.loadEpisodeMetadata() }
        .onChange(of: model.completed) { _, complete in if complete { close() } }
        .onExitCommand { close() }
        .onDisappear { model.close() }
    }
    private func close() { model.close(); dismiss() }
}


/// The saved position is information; only the three playback choices take focus.
struct TVResumePrompt: View {
    let title: String
    let position: String
    let resume: () -> Void
    let restart: () -> Void
    let back: () -> Void
    @FocusState private var focusedAction: Action?
    private enum Action { case resume, restart, back }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 56, weight: .bold))
                    .multilineTextAlignment(.center).lineLimit(2)
                Text(L("Continue from %@?", position))
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
                    .accessibilityIdentifier("resume-position")
            }
            .shadow(color: .black.opacity(0.5), radius: 12, y: 3)

            HStack(spacing: 28) {
                Button(action: resume) {
                    Label(L("Resume"), systemImage: "play.fill").frame(minWidth: 240)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                .focused($focusedAction, equals: .resume)
                .accessibilityIdentifier("resume-playback")
                Button(action: restart) {
                    Label(L("Start from beginning"), systemImage: "arrow.counterclockwise").frame(minWidth: 340)
                }
                .buttonStyle(.bordered).tint(.white.opacity(0.2)).foregroundStyle(.white)
                .focused($focusedAction, equals: .restart)
                .accessibilityIdentifier("restart-playback")
            }
            .padding(.top, 40)

            Button(action: back) {
                Label(L("Back"), systemImage: "arrow.backward")
                    .font(.system(size: 26, weight: .medium))
            }
            // A custom style: .plain on tvOS still draws its own lifted card
            // around the capsule.
            .buttonStyle(BackPillStyle())
            .focused($focusedAction, equals: .back)
            .accessibilityIdentifier("resume-back")
            .padding(.top, 48)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 1100).padding(.horizontal, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .focusSection()
        .defaultFocus($focusedAction, .resume)
    }
}

struct PlayerView: View {
    @AppStorage("seekInterval") private var seekInterval = 10
    let controller: EmbeddedPlayer
    let title: String
    let streamStatus: StreamStatus?
    var episodeLabel: String? = nil
    var intro: ClosedRange<Double>? = nil
    let close: () -> Void
    @State private var showControls = true
    @State private var activity = Date()
    @State private var trackMenu: TrackMenu?
    @State private var pausedSeekPosition: Double?
    /// While playing, swipes move this target; the player seeks once they stop.
    @State private var scrubTarget: Double?
    /// Where a touchpad swipe on the timeline started, while it lasts.
    @State private var panStart: Double?
    @State private var panEnded = Date.distantPast
    @State private var preferredControl: Control = .play
    @FocusState private var focusedTrack: Int?
    @FocusState private var focusedControl: Control?
    private enum Control { case close, timeline, backward, play, forward, audio, subtitles, surface, skipIntro }
    private var displayedPosition: Double { pausedSeekPosition ?? scrubTarget ?? controller.seconds }
    /// Until a second before the intro ends.
    private var inIntro: Bool {
        guard let intro, controller.failure == nil else { return false }
        return controller.seconds >= intro.lowerBound && controller.seconds < intro.upperBound - 1
    }
    private enum TrackMenu: String, Identifiable { case audio, subtitles; var id: String { rawValue } }
    var body: some View {
        ZStack {
            Color.black
            VideoSurface(controller: controller).id(ObjectIdentifier(controller))
            if !showControls {
                Button { revealControls() } label: { Color.clear }
                    // No system focus effect: tvOS would paint the focused,
                    // screen-sized button white over the video.
                    .buttonStyle(InvisibleButtonStyle()).focusEffectDisabled().focused($focusedControl, equals: .surface)
                    .accessibilityLabel(L("Show playback controls"))
            }
            if controller.buffering && !controller.playing && controller.failure == nil {
                PlaybackBufferingIndicator()
            }
            if let failure = controller.failure {
                VStack(spacing: 25) {
                    Text(failure).multilineTextAlignment(.center)
                    Button(L("Close player"), action: close)
                }.padding(50).frame(maxWidth: 800).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
            } else if showControls {
                VStack {
                    HStack {
                        Button(action: close) { Label(L("Close"), systemImage: "xmark") }.labelStyle(.iconOnly)
                            .focused($focusedControl, equals: .close)
                            // The close button is above the time label, not the
                            // timeline, so the focus engine finds nothing below it.
                            .onMoveCommand { if $0 == .down { focusedControl = .timeline } }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.headline).lineLimit(1)
                            if let episodeLabel { Text(episodeLabel).font(.subheadline).foregroundStyle(.white.opacity(0.7)).accessibilityIdentifier("playback-episode") }
                        }
                        Spacer()
                    }
                    Spacer()
                    VStack(spacing: 22) {
                        HStack {
                            Text(ResumeEntry.time(displayedPosition)).monospacedDigit().accessibilityIdentifier("playback-position")
                            timeline
                            Text(ResumeEntry.time(controller.duration)).monospacedDigit()
                        }
                        HStack(spacing: 45) {
                            Button { seek(by: -Double(seekInterval)); revealControls() } label: { Label(L("Back %ld seconds", seekInterval), systemImage: "gobackward.\(seekInterval)").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .backward).accessibilityIdentifier("seek-backward")
                            Button { togglePlayback(); revealControls() } label: {
                                Label(controller.playing ? L("Pause") : L("Play"), systemImage: controller.playing ? "pause.fill" : "play.fill")
                            }.labelStyle(.iconOnly).focused($focusedControl, equals: .play)
                                .accessibilityIdentifier("toggle-playback")
                            Button { seek(by: Double(seekInterval)); revealControls() } label: { Label(L("Forward %ld seconds", seekInterval), systemImage: "goforward.\(seekInterval)").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .forward).accessibilityIdentifier("seek-forward")
                            Button { trackMenu = .audio; revealControls() } label: { Label(L("Audio"), systemImage: "waveform").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .audio)
                            Button { trackMenu = .subtitles; revealControls() } label: { Label(L("Subtitles"), systemImage: "captions.bubble").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .subtitles)
                        }.focusSection()
                    }.padding(.horizontal, 25).padding(.vertical, 20)
                }.padding(60).onAppear { focusedControl = preferredControl }.background {
                    VStack {
                        LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).frame(height: 220)
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 300)
                    }.ignoresSafeArea()
                }.buttonStyle(PlayerControlStyle())
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if inIntro && trackMenu == nil {
                Button {
                    pausedSeekPosition = nil; scrubTarget = nil
                    if let intro { controller.seek(to: intro.upperBound) }
                    if !showControls { focusedControl = .surface }
                } label: {
                    Label(L("Skip Intro"), systemImage: "forward.end.fill").font(.system(size: 28, weight: .semibold))
                }
                .buttonStyle(SkipIntroStyle()).focused($focusedControl, equals: .skipIntro)
                .accessibilityIdentifier("skip-intro")
                .padding(.trailing, 90).padding(.bottom, showControls ? 250 : 90)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: inIntro)
        .onChange(of: inIntro) { _, now in
            if now && !showControls { focusedControl = .skipIntro }
            else if !now && focusedControl == .skipIntro { focusedControl = showControls ? .play : .surface }
        }
        .disabled(trackMenu != nil)
        .ignoresSafeArea()
        .defaultFocus($focusedControl, preferredControl)
        .onPlayPauseCommand { togglePlayback(); revealControls() }
        .onMoveCommand { direction in
            guard trackMenu == nil, controller.failure == nil else { return }
            if !showControls {
                if direction == .left || direction == .right {
                    seek(by: direction == .left ? -Self.clickStep : Self.clickStep)
                    revealControls(focusing: .timeline)
                    return
                }
            }
            revealControls()
        }
        .onChange(of: focusedControl) { _, _ in activity = Date() }
        .task(id: [scrubTarget, panStart]) {
            guard let target = scrubTarget, panStart == nil else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            controller.seek(to: target)
            // Keep showing the target until the player reports the new time.
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            scrubTarget = nil
        }
        .task(id: activity) {
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            if trackMenu == nil && focusedControl != .timeline && controller.playing && controller.failure == nil {
                showControls = false
                focusedControl = inIntro ? .skipIntro : .surface
            }
        }
        .overlay {
            if let menu = trackMenu {
                let tracks = menu == .audio ? controller.audioTracks : controller.subtitleTracks.filter { $0.id >= 0 }
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Text(menu == .audio ? L("Audio") : L("Subtitles")).font(.system(size: 36, weight: .semibold))
                            Spacer()
                            Button(L("Back")) { trackMenu = nil; revealControls() }.buttonStyle(.bordered)
                                .focused($focusedTrack, equals: -999)
                        }
                        ScrollView {
                            VStack(spacing: 12) {
                                if menu == .subtitles {
                                    Button { controller.player.currentVideoSubTitleIndex = -1; trackMenu = nil; revealControls() } label: {
                                        trackLabel(L("Off"), selected: controller.player.currentVideoSubTitleIndex == -1)
                                    }.buttonStyle(TVSelectionRowStyle()).focused($focusedTrack, equals: -1)
                                }
                                ForEach(tracks) { track in
                                    Button {
                                        if menu == .audio { controller.player.currentAudioTrackIndex = track.id }
                                        else { controller.player.currentVideoSubTitleIndex = track.id }
                                        trackMenu = nil
                                        revealControls()
                                    } label: {
                                        trackLabel(track.name, selected: menu == .audio ? controller.player.currentAudioTrackIndex == track.id : controller.player.currentVideoSubTitleIndex == track.id)
                                    }.buttonStyle(TVSelectionRowStyle()).focused($focusedTrack, equals: Int(track.id))
                                }
                                if tracks.isEmpty { Text(L("No tracks available yet.")).foregroundStyle(.secondary).padding(24) }
                            }.padding(4)
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: min(480, CGFloat(max(1, tracks.count + (menu == .subtitles ? 1 : 0))) * 96))
                    }
                    .padding(40).frame(width: 820)
                    .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 24))
                    .focusSection()
                }
                .onAppear {
                    focusedTrack = menu == .audio ? (tracks.isEmpty ? -999 : Int(controller.player.currentAudioTrackIndex)) : Int(controller.player.currentVideoSubTitleIndex)
                }
            }
        }
        .onExitCommand {
            if trackMenu != nil { trackMenu = nil; revealControls() }
            else { close() }
        }

    }
    private func trackLabel(_ name: String, selected: Bool) -> some View {
        HStack(spacing: 20) {
            Text(name).font(.system(size: 27, weight: .medium))
            Spacer()
            Image(systemName: "checkmark").opacity(selected ? 1 : 0)
        }.accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var timeline: some View {
        let focused = focusedControl == .timeline
        let fraction = min(1, max(0, displayedPosition / max(1, controller.duration)))
        return Button { togglePlayback(); revealControls() } label: {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - 24)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(focused ? 0.4 : 0.2))
                        .frame(width: width, height: focused ? 12 : 8)
                    Capsule().fill(Color.torrentAccent)
                        .frame(width: width * fraction, height: focused ? 12 : 8)
                    Circle().fill(focused ? Color.white : .torrentAccent)
                        .frame(width: focused ? 24 : 14, height: focused ? 24 : 14)
                        .offset(x: width * fraction - (focused ? 12 : 7))
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
            }
            .frame(height: 44)
        }
        .buttonStyle(InvisibleButtonStyle())
        .focusEffectDisabled()
        .focused($focusedControl, equals: .timeline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Playback position"))
        .accessibilityValue("\(ResumeEntry.time(displayedPosition)) / \(ResumeEntry.time(controller.duration))")
        .accessibilityIdentifier("playback-timeline")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { seek(by: Self.clickStep) }
            else if direction == .decrement { seek(by: -Self.clickStep) }
        }
        .background {
            // A swipe on the touchpad scrubs by its length, as in the system
            // player; a click on the edge of the remote jumps 10 seconds.
            RemotePanCatcher(enabled: focused && trackMenu == nil && controller.duration > 0,
                             began: { panStart = displayedPosition; activity = Date() },
                             changed: { fraction in
                                 guard let start = panStart else { return }
                                 move(to: start + Double(fraction) * scrubSpan)
                             },
                             ended: { panStart = nil; panEnded = Date() })
        }
        .onMoveCommand { direction in
            // A swipe also sends a move command; the pan already handled it.
            let swiping = panStart != nil || Date().timeIntervalSince(panEnded) < 0.4
            switch direction {
            case .left: if !swiping { seek(by: -Self.clickStep) }
            case .right: if !swiping { seek(by: Self.clickStep) }
            case .down: focusedControl = .play
            case .up: focusedControl = .close
            default: break
            }
            activity = Date()
        }
    }
    /// Remote clicks on the timeline jump like the system player, whatever
    /// the setting for the two seek buttons is.
    private static let clickStep = 10.0
    /// The seconds one swipe across the whole touchpad covers: a quarter of
    /// the video, but at least 2 and at most 30 minutes.
    private var scrubSpan: Double { min(1800, max(120, controller.duration / 4)) }
    private func seek(by offset: Double) { move(to: displayedPosition + offset) }
    private func move(to position: Double) {
        guard controller.duration > 0, controller.player.isSeekable else { return }
        let position = max(0, min(controller.duration - 1, position))
        if controller.player.state == .paused || pausedSeekPosition != nil {
            // VLC reports the old time until paused playback resumes. Keep the
            // selected position here so repeated presses accumulate correctly.
            pausedSeekPosition = position
        } else {
            // VLC also reports the old time for a moment after a seek while
            // playing, so a quick series of relative seeks would not add up.
            scrubTarget = position
        }
        activity = Date()
    }
    private func togglePlayback() {
        if let position = pausedSeekPosition {
            controller.seek(to: position)
            pausedSeekPosition = nil
            controller.player.play()
        } else {
            controller.toggle()
        }
    }
    private func revealControls(focusing target: Control? = nil) {
        let wasHidden = !showControls
        if let target { preferredControl = target }
        else if wasHidden { preferredControl = .play }
        showControls = true
        if let target { focusedControl = target }
        else if wasHidden { focusedControl = .play }
        activity = Date()
    }
}

/// "Skip intro": a dark pill that turns white with focus, with no lift.
struct SkipIntroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Pill(configuration: configuration) }
    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? .black : .white)
                .padding(.horizontal, 34).frame(height: 76)
                .background(focused ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.6)), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0 : 0.45), lineWidth: 2))
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

/// A quiet text button that becomes a white capsule with focus, with no lift.
struct BackPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Pill(configuration: configuration) }
    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? .black : .white.opacity(0.65))
                .padding(.horizontal, 28).padding(.vertical, 16)
                .background(focused ? Color.white : .clear, in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.contentShape(Rectangle()) }
}

struct PlayerControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ControlLabel(content: configuration.label)
    }
    struct ControlLabel<Content: View>: View {
        let content: Content
        @Environment(\.isFocused) private var focused
        var body: some View {
            content.font(.system(size: 30, weight: .medium)).padding(20)
                .foregroundStyle(focused ? .black : .white)
                .background(focused ? .white : .white.opacity(0.08), in: Circle())
        }
    }
}

/// Reports horizontal swipes on the Siri Remote touchpad. The recognizer sits
/// on the window, because touches go to the focused view, not to this one.
private struct RemotePanCatcher: UIViewRepresentable {
    let enabled: Bool
    let began: () -> Void
    /// The swipe so far, as a share of the touchpad width (−1…1).
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeUIView(context: Context) -> Host { Host() }
    func updateUIView(_ view: Host, context: Context) {
        view.enabled = enabled; view.began = began; view.changed = changed; view.ended = ended
        if !enabled, view.pan.state == .changed || view.pan.state == .began {
            view.pan.isEnabled = false; view.pan.isEnabled = true
        }
    }

    final class Host: UIView {
        let pan = UIPanGestureRecognizer()
        private let rules = Rules()
        var enabled = false
        var began: () -> Void = {}
        var changed: (CGFloat) -> Void = { _ in }
        var ended: () -> Void = {}

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            rules.host = self
            pan.delegate = rules
            pan.addTarget(self, action: #selector(handle))
        }
        required init?(coder: NSCoder) { fatalError() }

        override func willMove(toWindow newWindow: UIWindow?) {
            pan.view?.removeGestureRecognizer(pan)
            newWindow?.addGestureRecognizer(pan)
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            let width = max(1, pan.view?.bounds.width ?? 1920)
            switch pan.state {
            case .began: began()
            case .changed: changed(pan.translation(in: pan.view).x / width)
            case .ended, .cancelled, .failed: ended()
            default: break
            }
        }

    }

    /// Horizontal swipes only; vertical ones still move focus.
    final class Rules: NSObject, UIGestureRecognizerDelegate {
        weak var host: Host?
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard host?.enabled == true, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
