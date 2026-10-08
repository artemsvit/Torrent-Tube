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
                PlayerView(controller: controller, title: request.title, streamStatus: model.streamStatus) { close() }

            } else {
                ZStack(alignment: .leading) {
                    ArtworkView(url: request.artwork, background: true)
                    LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.6), .black.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            Text(request.title).font(.system(size: 56, weight: .bold)).lineLimit(2)
                            if let error = model.error {
                                ErrorPanel(message: error) { Task { await model.prepare() } }
                            } else if let resumeEntry = model.resumeEntry {
                                Text(L("Continue from %@?", resumeEntry.displayPosition)).font(.system(size: 30)).foregroundStyle(.white.opacity(0.8))
                                HStack(spacing: 28) {
                                    Button(L("Resume")) { model.openPlayer(at: resumeEntry.seconds) }
                                    Button(L("Start from beginning")) { model.openPlayer(at: 0) }
                                }
                            } else if let prepared = model.prepared, !model.loading {
                                Text(request.episode.map { L("Choose a file for episode %ld", $0) } ?? L("Choose an episode")).font(.system(size: 30, weight: .semibold))
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 32) {
                                        ForEach(prepared.files) { file in
                                            let identity = EpisodeIdentity.parse(file.name)
                                            let episode = identity.flatMap { identity in model.episodeMetadata[identity.season]?.first { $0.number == identity.episode } }
                                            Button { Task { await model.start(file: file.index) } } label: {
                                                VStack(alignment: .leading, spacing: 16) {
                                                    ArtworkView(url: episode?.still ?? request.artwork).frame(width: 380, height: 214).clipShape(RoundedRectangle(cornerRadius: 12))
                                                    Text(episode.map { "\($0.number). \($0.name)" } ?? file.name).font(.system(size: 26, weight: .semibold)).lineLimit(2)
                                                    if let identity { Text(L("Season %ld · Episode %ld", identity.season, identity.episode)).font(.system(size: 22)).foregroundStyle(.secondary) }
                                                }.frame(width: 380, alignment: .leading)
                                            }.buttonStyle(CinemaCardStyle())
                                        }
                                    }.padding(.vertical, 18).padding(.horizontal, 12)
                                }.focusSection()
                            }
                            Button(L("Back")) { close() }
                        }.padding(80)
                    }
                    if model.loading {
                        ProgressView(L("Preparing your stream…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.background(.black)
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
    let close: () -> Void
    @State private var showControls = true
    @State private var activity = Date()
    @State private var trackMenu: TrackMenu?
    @FocusState private var focusedTrack: Int?
    @FocusState private var focusedControl: Control?
    private enum Control { case close, backward, play, forward, audio, subtitles, surface }
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
                    ProgressView()
                    Text(L("Buffering…")).font(.headline)
                    if let streamStatus, !streamStatus.ready {
                        Text(L("%ld%% ready", Int(streamStatus.headProgress ?? 0)))
                            .foregroundStyle(.secondary)
                    }
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
                        Text(title).font(.headline).lineLimit(1)
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
                focusedControl = .surface
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
