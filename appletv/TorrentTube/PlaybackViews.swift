import SwiftUI

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
        Group {
            if let controller = model.controller {
                PlayerView(controller: controller, title: request.title, streamStatus: model.streamStatus, episodeLabel: model.episodeLabel, intro: model.intro) { close() }

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
                            } else if let resumeEntry = model.resumeEntry {
                                VStack(alignment: .leading, spacing: 28) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 26, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                        Text(L("Continue from %@?", resumeEntry.displayPosition))
                                            .font(.system(size: 30, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.14), in: Capsule())

                                    HStack(spacing: 24) {
                                        Button {
                                            model.openPlayer(at: resumeEntry.seconds)
                                        } label: {
                                            Label(L("Resume"), systemImage: "play.fill")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.white)
                                        .foregroundStyle(.black)

                                        Button {
                                            model.openPlayer(at: 0)
                                        } label: {
                                            Label(L("Start from beginning"), systemImage: "arrow.counterclockwise")
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.white.opacity(0.25))
                                        .foregroundStyle(.white)

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
    @FocusState private var focusedTrack: Int?
    @FocusState private var focusedControl: Control?
    private enum Control { case close, backward, play, forward, audio, subtitles, surface, skipIntro }
    /// Until a second before the intro ends.
    private var inIntro: Bool {
        guard let intro, controller.failure == nil else { return false }
        return controller.seconds >= intro.lowerBound && controller.seconds < intro.upperBound - 1
    }
    private enum TrackMenu: String, Identifiable { case audio, subtitles; var id: String { rawValue } }
    var body: some View {
        ZStack {
            Color.black
            VideoSurface(controller: controller)
            if !showControls {
                Button { revealControls() } label: { Color.clear }
                    // No system focus effect: tvOS would paint the focused,
                    // screen-sized button white over the video.
                    .buttonStyle(InvisibleButtonStyle()).focusEffectDisabled().focused($focusedControl, equals: .surface)
                    .accessibilityLabel(L("Show playback controls"))
            }
            if controller.buffering && !controller.playing && controller.failure == nil {
                VStack(spacing: 20) {
                    ProgressView().tint(.white)
                    Text(L("Buffering…")).font(.headline)
                }.padding(35).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.headline).lineLimit(1)
                            if let episodeLabel { Text(episodeLabel).font(.subheadline).foregroundStyle(.white.opacity(0.7)) }
                        }
                        Spacer()
                    }
                    Spacer()
                    VStack(spacing: 22) {
                        HStack {
                            Text(ResumeEntry.time(controller.seconds)).monospacedDigit().accessibilityIdentifier("playback-position")
                            ProgressView(value: min(controller.seconds, max(1, controller.duration)), total: max(1, controller.duration))
                            Text(ResumeEntry.time(controller.duration)).monospacedDigit()
                        }
                        HStack(spacing: 45) {
                            Button { controller.seek(by: -Double(seekInterval)); revealControls() } label: { Label(L("Back %ld seconds", seekInterval), systemImage: "gobackward.\(seekInterval)").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .backward).accessibilityIdentifier("seek-backward")
                            Button { controller.toggle(); revealControls() } label: {
                                Label(controller.playing ? L("Pause") : L("Play"), systemImage: controller.playing ? "pause.fill" : "play.fill")
                            }.labelStyle(.iconOnly).focused($focusedControl, equals: .play)
                            Button { controller.seek(by: Double(seekInterval)); revealControls() } label: { Label(L("Forward %ld seconds", seekInterval), systemImage: "goforward.\(seekInterval)").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .forward).accessibilityIdentifier("seek-forward")
                            Button { trackMenu = .audio; revealControls() } label: { Label(L("Audio"), systemImage: "waveform").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .audio)
                            Button { trackMenu = .subtitles; revealControls() } label: { Label(L("Subtitles"), systemImage: "captions.bubble").labelStyle(.iconOnly) }
                                .focused($focusedControl, equals: .subtitles)
                        }.focusSection()
                    }.padding(.horizontal, 25).padding(.vertical, 20)
                }.padding(60).background {
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
        .defaultFocus($focusedControl, .play)
        .onPlayPauseCommand { controller.toggle(); revealControls() }
        .onMoveCommand { direction in
            if !showControls {
                if direction == .left { controller.seek(by: -Double(seekInterval)) }
                if direction == .right { controller.seek(by: Double(seekInterval)) }
            }
            revealControls()
        }
        .onChange(of: focusedControl) { _, _ in activity = Date() }
        .task(id: activity) {
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            if trackMenu == nil && controller.playing && controller.failure == nil {
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
    private func revealControls() {
        if !showControls { focusedControl = .play }
        showControls = true
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
