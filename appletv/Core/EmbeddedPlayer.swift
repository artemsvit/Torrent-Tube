import SwiftUI
import Observation
#if os(tvOS)
import TVVLCKit
#elseif os(macOS)
import VLCKit
#else
import MobileVLCKit
#endif

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let source: PlaybackSource
    let title: String
    var artwork: String? = nil
    var tmdbID: Int? = nil
    var season: Int? = nil
    var episode: Int? = nil
    /// The title's other folders on the server (a season each, usually):
    /// where the next season is found when the last episode here ends.
    var seasonSources: [PlaybackSource] = []
}

@MainActor @Observable
final class EmbeddedPlayer {
    @ObservationIgnored let player = VLCMediaPlayer()
    var seconds: Double = 0
    var duration: Double = 0
    var playing = false
    var buffering = true
    var failure: String?
    var ended = false
    @ObservationIgnored private var resumePosition: Double
    @ObservationIgnored private var didResume = false
    @ObservationIgnored private var started = false

    @ObservationIgnored private let subtitleURL: URL?
    /// The subtitle file, saved on the device, and whether VLC has it yet.
    @ObservationIgnored private var subtitleFile: URL?
    @ObservationIgnored private var subtitleAttached = false
    @ObservationIgnored private var subtitleSelected = false
    /// VLC's id for the added subtitle track - named by language in the menu.
    @ObservationIgnored private var externalSubtitleID: Int32?

    @ObservationIgnored private let subtitleName: String

    init(url: URL, resumePosition: Double, audioURL: URL? = nil, subtitleURL: URL? = nil, subtitleName: String? = nil) {
        self.resumePosition = resumePosition
        self.subtitleURL = subtitleURL
        self.subtitleName = subtitleName ?? "Subtitles"
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=2500")
        if let audioURL { media.addOption(":input-slave=\(audioURL.absoluteString)") }
        player.media = media
    }
    func attach(to view: PlatformView) {
        player.drawable = view
        if !started {
            started = true
            player.play()
            // A separate subtitle file (trailers). VLC drops a track added before
            // the video opens, and fetches remote ones unreliably - so the file is
            // saved first and attached once playback runs (see refresh()).
            if let subtitleURL { Task { await downloadSubtitles(subtitleURL) } }
        }
    }
    private func downloadSubtitles(_ url: URL) async {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return }
        // Its own folder, named after the language - VLC shows the file name in the track menu.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(subtitleName).vtt")
        guard (try? data.write(to: file)) != nil else { return }
        subtitleFile = file
        attachSubtitlesIfReady()
    }
    private func attachSubtitlesIfReady() {
        guard !subtitleAttached, let subtitleFile, player.isPlaying else { return }
        subtitleAttached = true
        player.addPlaybackSlave(subtitleFile, type: .subtitle, enforce: true)
    }
    func refresh() {
        attachSubtitlesIfReady()
        // Once VLC lists the added track, make sure it is the one shown.
        if subtitleAttached && !subtitleSelected, let track = subtitleTracks.last(where: { $0.id >= 0 }) {
            subtitleSelected = true
            externalSubtitleID = track.id
            player.currentVideoSubTitleIndex = track.id
        }
        seconds = max(0, Double(player.time.intValue) / 1000)
        duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
        playing = player.isPlaying
        buffering = player.state == .opening || (player.state == .buffering && !player.isPlaying)
        if player.state == .error { failure = L("This file could not be played. Try another release.") }
        ended = player.state == .ended
        if !didResume && duration > 0 && player.isSeekable {
            didResume = true
            if resumePosition > 0 { seek(to: resumePosition) }
        }
    }
    func pause() { player.pause(); playing = false }
    func toggle() { if player.isPlaying { player.pause() } else { player.play() } }
    func seek(by offset: Double) { seek(to: seconds + offset) }
    func seek(to value: Double) {
        guard duration > 0, player.isSeekable else { return }
        guard value.isFinite else { return }
        seconds = max(0, min(duration - 1, value))
        player.time = VLCTime(int: Int32(min(Double(Int32.max), seconds * 1000)))
    }
    func stop() {
        player.stop(); player.drawable = nil
        if let subtitleFile { try? FileManager.default.removeItem(at: subtitleFile.deletingLastPathComponent()) }
    }

    struct Track: Identifiable { let id: Int32; let name: String }
    var audioTracks: [Track] { tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes) }
    var subtitleTracks: [Track] {
        // VLC calls an added file "Track 1"; show its language instead.
        tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes).map { track in
            track.id == externalSubtitleID ? Track(id: track.id, name: subtitleName) : track
        }
    }
    private func tracks(names: [Any]?, indexes: [Any]?) -> [Track] {
        zip(names ?? [], indexes ?? []).compactMap { name, index in
            guard let number = index as? NSNumber else { return nil }
            return Track(id: number.int32Value, name: String(describing: name))
        }
    }
}

#if os(macOS)
struct VideoSurface: NSViewRepresentable {
    let controller: EmbeddedPlayer
    func makeNSView(context: Context) -> NSView { Surface(controller: controller) }
    func updateNSView(_ nsView: NSView, context: Context) {}
    /// VLC's own video view, handed to the player only once it is in the
    /// window - given a view outside one, VLC opens a separate window.
    final class Surface: VLCVideoView {
        let controller: EmbeddedPlayer
        private var attached = false
        init(controller: EmbeddedPlayer) {
            self.controller = controller
            super.init(frame: .zero)
            backColor = .black
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !attached else { return }
            attached = true
            MainActor.assumeIsolated { controller.attach(to: self) }
        }
    }
}
#else
struct VideoSurface: UIViewRepresentable {
    let controller: EmbeddedPlayer
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) { }
}
#endif

