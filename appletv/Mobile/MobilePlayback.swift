import SwiftUI
import AVFAudio

struct MobilePlayback: View {
    let request: PlaybackRequest
    let api: TorrentTubeAPI
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ResumeHistory.self) private var history
    @State private var model: PlaybackCoordinator
    init(request: PlaybackRequest, api: TorrentTubeAPI) {
        self.request = request; self.api = api
        _model = State(initialValue: PlaybackCoordinator(request: request, api: api))
    }
    var body: some View {
        Group {
            if let controller = model.controller {
                MobilePlayer(controller: controller, title: request.title, streamStatus: model.streamStatus,
                             retry: { Task { await model.prepare() } }, close: close)
            } else {
                NavigationStack {
                    List {
                        Section { Text(request.title).font(.title2.bold()) }
                        if model.suspended {
                            Section {
                                Text(L("Playback paused while the app was in the background."))
                                Button(L("Reconnect and resume")) { Task { await model.prepare() } }
                            }
                        } else if let error = model.error {
                            MobileError(message: error) { Task { await model.prepare() } }
                        } else if model.loading {
                            ProgressView(L("Preparing your stream…"))
                        } else if let resume = model.resumeEntry {
                            Section(L("Continue from %@?", resume.displayPosition)) {
                                Button(L("Resume")) { model.openPlayer(at: resume.seconds) }.accessibilityIdentifier("resume-playback")
                                Button(L("Start from beginning")) { model.openPlayer(at: 0) }
                            }
                        } else if let prepared = model.prepared {
                            Section(L("Choose a file")) {
                                ForEach(prepared.files) { file in
                                    Button { Task { await model.start(file: file.index) } } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(file.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                        }.padding(.vertical, 6)
                                    }.accessibilityIdentifier("video-file-\(file.index)")
                                }
                            }
                        }
                    }.toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Close"), action: close) } }
                }
            }
        }
        .task { model.history = history; await model.prepare() }
        .task(id: model.prepared?.id) { await model.loadEpisodeMetadata() }
        .onChange(of: model.completed) { _, complete in if complete { close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.suspend() }
            else if phase == .inactive { model.controller?.pause(); model.savePosition() }
        }
        .onDisappear { model.close() }
    }
    private func close() { model.close(); dismiss() }
}

struct MobilePlayer: View {
    let controller: EmbeddedPlayer
    let title: String
    let streamStatus: StreamStatus?
    let retry: () -> Void
    let close: () -> Void
    @AppStorage("seekInterval") private var skip = 10
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var visible = true
    @State private var activity = Date()
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var tracks: TrackMenu?
    private enum TrackMenu: String, Identifiable { case audio, subtitles; var id: String { rawValue } }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(controller: controller).id(ObjectIdentifier(controller)).ignoresSafeArea()
            Button { visible.toggle(); activity = Date() } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel(L("Show playback controls"))
            if controller.buffering && controller.failure == nil {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(L("Buffering…"))
                    if let streamStatus, !streamStatus.ready { Text(L("%ld%% ready", Int(streamStatus.headProgress ?? 0))) }
                }.padding(24).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false)
            }
            if let failure = controller.failure {
                VStack(spacing: 16) {
                    Text(failure).multilineTextAlignment(.center)
                    Button(L("Try again"), action: retry).buttonStyle(.borderedProminent)
                    Button(L("Close player"), action: close).buttonStyle(.bordered)
                }.padding(24).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).padding()
            } else if visible {
                VStack {
                    HStack {
                        control("Close", icon: "xmark", action: close).accessibilityIdentifier("close-player")
                        Text(title).font(.headline).lineLimit(2)
                        Spacer(minLength: 0)
                    }.padding(12).background(.black.opacity(0.65))
                    Spacer()
                    controls.padding(16).background(.black.opacity(0.75))
                }
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden(!visible)
        .persistentSystemOverlays(visible ? .automatic : .hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch { controller.failure = error.localizedDescription }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
                controller.pause(); reveal()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                controller.pause(); reveal()
            }
        }
        .task(id: activity) {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            if controller.playing, tracks == nil, !scrubbing, !voiceOver { visible = false }
        }
        .sheet(item: $tracks) { menu in trackSheet(menu) }
    }
    private var controls: some View {
        VStack(spacing: 8) {
            Slider(value: Binding(get: { scrubbing ? scrub : controller.seconds }, set: { scrub = $0 }),
                   in: 0...max(1, controller.duration), onEditingChanged: { editing in
                scrubbing = editing
                if !editing { controller.seek(to: scrub) }
                reveal()
            }).disabled(controller.duration <= 0)
                .accessibilityLabel(L("Playback position")).accessibilityIdentifier("playback-scrubber")
            HStack {
                Text(ResumeEntry.time(scrubbing ? scrub : controller.seconds)).accessibilityIdentifier("playback-position")
                Spacer(); Text(ResumeEntry.time(controller.duration))
            }.font(.caption.monospacedDigit())
            HStack(spacing: 4) {
                control("Audio", icon: "waveform") { tracks = .audio }
                Spacer(minLength: 0)
                control(L("Back %ld seconds", skip), icon: "gobackward.\(skip)") { controller.seek(by: -Double(skip)) }.accessibilityIdentifier("seek-backward")
                control(controller.playing ? "Pause" : "Play", icon: controller.playing ? "pause.fill" : "play.fill") { togglePlayback() }.accessibilityIdentifier("toggle-playback")
                control(L("Forward %ld seconds", skip), icon: "goforward.\(skip)") { controller.seek(by: Double(skip)) }.accessibilityIdentifier("seek-forward")
                Spacer(minLength: 0)
                control("Subtitles", icon: "captions.bubble") { tracks = .subtitles }
            }
        }
    }
    private func control(_ name: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { action(); reveal() } label: { Image(systemName: icon).font(.title2).frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel(L(name))
    }
    private func togglePlayback() {
        if !controller.playing {
            do { try AVAudioSession.sharedInstance().setActive(true) }
            catch { controller.failure = error.localizedDescription; return }
        }
        controller.toggle()
    }
    private func reveal() { visible = true; activity = Date() }
    private func trackSheet(_ menu: TrackMenu) -> some View {
        NavigationStack {
            List {
                if menu == .subtitles {
                    trackRow(name: L("Off"), selected: controller.player.currentVideoSubTitleIndex == -1) { controller.player.currentVideoSubTitleIndex = -1 }
                }
                let available = menu == .audio ? controller.audioTracks : controller.subtitleTracks.filter { $0.id >= 0 }
                ForEach(available) { track in
                    trackRow(name: track.name, selected: menu == .audio ? controller.player.currentAudioTrackIndex == track.id : controller.player.currentVideoSubTitleIndex == track.id) {
                        if menu == .audio { controller.player.currentAudioTrackIndex = track.id }
                        else { controller.player.currentVideoSubTitleIndex = track.id }
                    }
                }
                if available.isEmpty { Text(L("No tracks available yet.")).foregroundStyle(.secondary) }
            }.navigationTitle(L(menu == .audio ? "Audio" : "Subtitles"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { tracks = nil; reveal() } } }
        }.presentationDetents([.medium, .large])
    }
    private func trackRow(name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); tracks = nil; reveal() } label: {
            HStack { Text(name); Spacer(); if selected { Image(systemName: "checkmark") } }
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MobileTrailer: View {
    let trailer: Trailer
    let api: TorrentTubeAPI
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: EmbeddedPlayer?
    @State private var error: String?
    @State private var loading = false
    @State private var suspended = false
    @State private var position: Double = 0
    @State private var generation = UUID()
    var body: some View {
        Group {
            if let controller {
                MobilePlayer(controller: controller, title: trailer.name, streamStatus: nil, retry: { Task { await prepare() } }, close: close)
                    .task {
                        while !Task.isCancelled {
                            controller.refresh()
                            if controller.ended { close(); return }
                            do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        }
                    }
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text(trailer.name).font(.title2.bold())
                        if suspended { Button(L("Reconnect and resume")) { Task { await prepare() } } }
                        else if let error { MobileError(message: error) { Task { await prepare() } } }
                        else { ProgressView(L("Preparing trailer…")) }
                    }.padding().toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Close"), action: close) } }
                }
            }
        }
        .task { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                position = controller?.seconds ?? position
                suspended = true; generation = UUID()
                controller?.stop(); controller = nil
            } else if phase == .inactive { controller?.pause() }
        }
        .onDisappear { generation = UUID(); controller?.stop() }
    }
    private func prepare() async {
        let current = UUID(); generation = current
        controller?.stop(); controller = nil; error = nil; suspended = false; loading = true
        defer { if current == generation { loading = false } }
        do {
            let stream: TrailerStreamResponse = try await api.post("api/trailer/stream", body: ["key": trailer.key, "subtitles": Localizer.shared.language == .uk ? "uk,en" : "en"])
            try Task.checkCancellation()
            guard current == generation else { return }
            controller = EmbeddedPlayer(url: try api.mediaURL(stream.url), resumePosition: position,
                                        audioURL: try stream.audioUrl.map(api.mediaURL), subtitleURL: try stream.subtitleUrl.map(api.mediaURL))
        } catch is CancellationError {} catch { if current == generation { self.error = error.localizedDescription } }
    }
    private func close() { generation = UUID(); controller?.stop(); dismiss() }
}
