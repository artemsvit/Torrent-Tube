import SwiftUI
import AVFAudio

private enum MobileAudioSession {
    // Audio-session changes can block. Keep them off the UI thread and preserve
    // activation/deactivation order when a player closes and another opens.
    private static let queue = DispatchQueue(label: "com.artsvit.torrenttube.mobile.audio-session")

    static func activate(completion: @escaping @MainActor @Sendable (String?) -> Void) {
        #if os(macOS)
        Task { @MainActor in completion(nil) }  // the Mac has no audio session to set up
        #else
        queue.async {
            let failure: String?
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
                failure = nil
            } catch { failure = error.localizedDescription }
            Task { @MainActor in completion(failure) }
        }
        #endif
    }

    static func deactivate() {
        #if !os(macOS)
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
}

/// A call, an alarm or unplugged headphones pause the video (iPhone and iPad).
private struct AudioInterruptions: ViewModifier {
    let pause: () -> Void
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                if (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { pause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { pause() }
            }
        #endif
    }
}

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
                MobilePlayer(controller: controller, title: request.title, streamStatus: model.streamStatus, episodeLabel: model.episodeLabel, artwork: request.artwork, intro: model.intro,
                             retry: { Task { await model.prepare() } }, close: close)
            } else {
                preparation
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
    private var preparation: some View {
        ZStack {
            MobilePlaybackBackdrop(artwork: request.artwork)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.1), in: Circle())
                    }.hapticButtonStyle(PlainButtonStyle()).accessibilityLabel(L("Close"))
                    Text(request.title).font(.headline).lineLimit(2)
                    Spacer(minLength: 0)
                }.padding(20)
                ScrollView {
                    VStack(spacing: 24) {
                        if model.suspended {
                            statusIcon("pause.circle")
                            Text(L("Playback paused while the app was in the background."))
                                .font(.title3.weight(.medium)).multilineTextAlignment(.center)
                            primaryAction("Reconnect and resume", icon: "play.fill") { Task { await model.prepare() } }
                                .accessibilityIdentifier("reconnect-playback")
                        } else if let error = model.error {
                            statusIcon("exclamationmark.circle")
                            Text(error).font(.body).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                            primaryAction("Try again", icon: "arrow.clockwise") { Task { await model.prepare() } }
                        } else if model.loading {
                            MobilePlaybackLoading(title: request.title, message: L("Preparing your stream…"))
                        } else if let resume = model.resumeEntry {
                            statusIcon("play.circle")
                            Text(L("Continue from %@?", resume.displayPosition)).font(.title2.bold()).multilineTextAlignment(.center)
                            primaryAction("Resume", icon: "play.fill") { model.openPlayer(at: resume.seconds) }
                                .accessibilityIdentifier("resume-playback")
                            Button(L("Start from beginning")) { model.openPlayer(at: 0) }
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                                .background(.white.opacity(0.1), in: Capsule()).hapticButtonStyle(PlainButtonStyle())
                        } else if let prepared = model.prepared {
                            Text(L("Choose a file")).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
                            LazyVStack(spacing: 10) {
                                ForEach(prepared.files) { file in
                                    Button { Task { await model.start(file: file.index) } } label: {
                                        HStack(spacing: 16) {
                                            Image(systemName: "play.circle").font(.title2).accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(file.name).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                                            .contentShape(RoundedRectangle(cornerRadius: 18))
                                    }.hapticButtonStyle(PlainButtonStyle()).multilineTextAlignment(.leading)
                                        .accessibilityIdentifier("video-file-\(file.index)")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 560).padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 300)
                }.defaultScrollAnchor(.center, for: .alignment)
                Spacer(minLength: 20)
            }
        }.foregroundStyle(.white).tint(.white).preferredColorScheme(.dark)
    }
    private func statusIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 48, weight: .light))
            .foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
    }
    private func primaryAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L(label), systemImage: icon).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.black).background(.white, in: Capsule())
        }.hapticButtonStyle(PlainButtonStyle())
    }
    @Environment(\.closeCover) private var closeCover
    private func close() { model.close(); if let closeCover { closeCover() } else { dismiss() } }
}

struct MobilePlaybackBackdrop: View {
    let artwork: String?
    var body: some View {
        ZStack {
            Color.appBase
            HeroBackdrop(url: artwork.flatMap { URL(string: higherResolution($0, backdrop: true)) }).opacity(0.3)
            LinearGradient(colors: [.black.opacity(0.25), Color.appBase], startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct MobilePlaybackLoading: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(.white)
            Text(title).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }.frame(maxWidth: 420)
    }
}

struct MobilePlayer: View {
    let controller: EmbeddedPlayer
    let title: String
    let streamStatus: StreamStatus?
    var episodeLabel: String? = nil
    var artwork: String? = nil
    var intro: ClosedRange<Double>? = nil
    let retry: () -> Void
    let close: () -> Void
    @AppStorage("seekInterval") private var skip = 10
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var audioReady = false
    @State private var audioRequest: UUID?
    @State private var visible = true
    @State private var activity = Date()
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var tracks: TrackMenu?
    private enum TrackMenu: String, Identifiable { case audio, subtitles; var id: String { rawValue } }
    var body: some View {
        #if os(macOS)
        // The Mac has its own player, in the way of QuickTime.
        MacPlayer(controller: controller, title: title, streamStatus: streamStatus, episodeLabel: episodeLabel, artwork: artwork, intro: intro, retry: retry, close: close)
        #else
        touchPlayer
        #endif
    }
    private var touchPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !audioReady || (controller.buffering && controller.seconds == 0) {
                MobilePlaybackBackdrop(artwork: artwork)
            }
            if audioReady {
                VideoSurface(controller: controller).id(ObjectIdentifier(controller)).ignoresSafeArea()
                    .opacity(controller.buffering && controller.seconds == 0 ? 0 : 1)
            }
            Button { visible.toggle(); activity = Date() } label: { Color.clear.contentShape(Rectangle()) }
                .hapticButtonStyle(PlainButtonStyle()).accessibilityLabel(L("Show playback controls"))
            if controller.buffering && controller.failure == nil {
                PlaybackBufferingIndicator()
            }
            if let failure = controller.failure {
                VStack(spacing: 16) {
                    Text(failure).multilineTextAlignment(.center)
                    Button(L("Try again"), action: retry).hapticButtonStyle(BorderedProminentButtonStyle())
                    Button(L("Close player"), action: close).hapticButtonStyle(BorderedButtonStyle())
                }.padding(24).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).padding()
            } else if visible {
                VStack {
                    HStack {
                        control("Close", icon: "xmark", action: close).accessibilityIdentifier("close-player")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.headline).lineLimit(2)
                            if let episodeLabel { Text(episodeLabel).font(.subheadline).foregroundStyle(.white.opacity(0.7)) }
                        }
                        Spacer(minLength: 0)
                    }.padding(12).background(.black.opacity(0.65))
                    Spacer()
                    controls.padding(16).background(.black.opacity(0.75))
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let intro, controller.failure == nil, controller.seconds >= intro.lowerBound, controller.seconds < intro.upperBound - 1 {
                Button { controller.seek(to: intro.upperBound) } label: {
                    Label(L("Skip Intro"), systemImage: "forward.end.fill").font(.headline)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(.black.opacity(0.6), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                }
                .accessibilityIdentifier("skip-intro")
                .padding(.trailing, 16).padding(.bottom, visible ? 150 : 32)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden(!visible)
        .persistentSystemOverlays(visible ? .automatic : .hidden)
        .onAppear {
            ScreenSleep.prevent(true)
            activateAudio(resuming: false)
        }
        .onDisappear {
            ScreenSleep.prevent(false)
            audioRequest = nil
            audioReady = false
            controller.pause()
            MobileAudioSession.deactivate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                // Discard pending completions so they cannot resume in the background.
                audioRequest = nil
            } else if !audioReady {
                activateAudio(resuming: false)
            }
        }
        .modifier(AudioInterruptions { audioRequest = nil; controller.pause(); reveal() })
        .task(id: activity) {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            if controller.playing, tracks == nil, !scrubbing, !voiceOver { visible = false }
        }
        .sheet(item: $tracks, onDismiss: reveal) { menu in
            MobileTrackSheet(controller: controller, subtitles: menu == .subtitles, title: title)
        }
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
                    .accessibilityIdentifier("audio-tracks")
                Spacer(minLength: 0)
                control(L("Back %ld seconds", skip), icon: "gobackward.\(skip)") { controller.seek(by: -Double(skip)) }.accessibilityIdentifier("seek-backward")
                control(controller.playing ? "Pause" : "Play", icon: controller.playing ? "pause.fill" : "play.fill") { togglePlayback() }.accessibilityIdentifier("toggle-playback")
                    .disabled(audioRequest != nil)
                control(L("Forward %ld seconds", skip), icon: "goforward.\(skip)") { controller.seek(by: Double(skip)) }.accessibilityIdentifier("seek-forward")
                Spacer(minLength: 0)
                control("Subtitles", icon: "captions.bubble") { tracks = .subtitles }
                    .accessibilityIdentifier("subtitle-tracks")
            }
        }
    }
    private func control(_ name: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { action(); reveal() } label: { Image(systemName: icon).font(.title2).frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel(L(name))
    }
    private func togglePlayback() {
        if controller.playing {
            controller.pause()
        } else {
            activateAudio(resuming: audioReady)
        }
    }
    private func activateAudio(resuming: Bool) {
        let request = UUID()
        audioRequest = request
        MobileAudioSession.activate { failure in
            // The view may have closed, become inactive, or requested activation again.
            guard audioRequest == request else { return }
            audioRequest = nil
            if let failure {
                controller.failure = failure
                return
            }
            if resuming { controller.toggle() }
            else { audioReady = true }
        }
    }
    private func reveal() { visible = true; activity = Date() }
}

/// The player uses the same dark surfaces and white actions as the catalog.
private struct MobileTrackSheet: View {
    let controller: EmbeddedPlayer
    let subtitles: Bool
    let title: String
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric private var rowHeight: CGFloat = 56

    private var available: [EmbeddedPlayer.Track] {
        subtitles ? [.init(id: -1, name: L("Off"))] + controller.subtitleTracks.filter { $0.id >= 0 }
                  : controller.audioTracks
    }
    private var selected: Int32 {
        subtitles ? controller.player.currentVideoSubTitleIndex : controller.player.currentAudioTrackIndex
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: subtitles ? "captions.bubble" : "waveform")
                    .font(.title3).frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                Text(L(subtitles ? "Subtitles" : "Audio")).font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(L("Done")) { dismiss() }
                    .font(.headline).padding(.horizontal, 18).frame(minHeight: 44)
                    .background(.white.opacity(0.12), in: Capsule())
                    .hapticButtonStyle(PlainButtonStyle()).accessibilityIdentifier("track-panel-done")
            }
            Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(available) { track in
                        let isSelected = selected == track.id
                        Button {
                            if subtitles { controller.player.currentVideoSubTitleIndex = track.id }
                            else { controller.player.currentAudioTrackIndex = track.id }
                            dismiss()
                        } label: {
                            HStack(spacing: 16) {
                                Text(track.id < 0 ? L("Off") : track.name)
                                    .font(.body.weight(isSelected ? .semibold : .regular))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(.white.opacity(isSelected ? 1 : 0.3))
                                    .frame(width: 24).accessibilityHidden(true)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .frame(minHeight: rowHeight)
                            .background(.white.opacity(isSelected ? 0.13 : 0.045), in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(isSelected ? 0.25 : 0.07), lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .hapticButtonStyle(PlainButtonStyle())
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("\(subtitles ? "subtitle" : "audio")-track-\(track.id)")
                    }
                    if available.isEmpty {
                        Text(L("No tracks available yet.")).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
        .foregroundStyle(.white).tint(.white)
        .presentationBackground(Color.appBase)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(min(540, 164 + CGFloat(max(1, available.count)) * (rowHeight + 8))), .large])
        .preferredColorScheme(.dark)
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
                        else { ProgressView() }
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
                                        audioURL: try stream.audioUrl.map(api.mediaURL), subtitleURL: try stream.subtitleUrl.map(api.mediaURL), subtitleName: stream.subtitleName)
        } catch is CancellationError {} catch { if current == generation { self.error = error.localizedDescription } }
    }
    @Environment(\.closeCover) private var closeCover
    private func close() { generation = UUID(); controller?.stop(); if let closeCover { closeCover() } else { dismiss() } }
}
