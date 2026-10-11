import SwiftUI
import Observation
#if os(tvOS)
import TVVLCKit
#elseif os(macOS)
import VLCKit
#else
import MobileVLCKit
#endif

/// The player and its view, handed to the stop queue.
private struct StoppingPlayer: @unchecked Sendable {
    let player: VLCMediaPlayer
    let view: Any?
}
/// The view, handed back to the main thread to be freed there.
private struct ViewToRelease: @unchecked Sendable { let view: Any? }

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

/// Subtitle choices in Settings: shown in films and shows (on by default),
/// shown in trailers (off by default), and how large they are.
enum SubtitleSettings {
    static let filmsKey = "subtitlesInFilms"
    static let trailersKey = "subtitlesInTrailers"
    static let sizeKey = "subtitleSize"
    static var films: Bool { UserDefaults.standard.object(forKey: filmsKey) as? Bool ?? true }
    static var trailers: Bool { UserDefaults.standard.bool(forKey: trailersKey) }
    static var size: SubtitleSize { SubtitleSize(rawValue: UserDefaults.standard.string(forKey: sizeKey) ?? "") ?? .medium }
}

enum SubtitleSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var name: String { L(rawValue.capitalized) }
    /// VLC's relative font size: the video's height divided by this. 16 is VLC's own size.
    var relativeSize: Int { switch self { case .small: 22; case .medium: 16; case .large: 12 } }
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
    /// Paused by the viewer: VLC can say "buffering" after a seek while
    /// paused, but nothing is loading that the viewer waits for.
    @ObservationIgnored private(set) var userPaused = false

    @ObservationIgnored private let subtitleURL: URL?
    /// The subtitle file, saved on the device, and whether VLC has it yet.
    @ObservationIgnored private var subtitleFile: URL?
    @ObservationIgnored private var subtitleAttached = false
    @ObservationIgnored private var subtitleSelected = false
    /// VLC's id for the added subtitle track - named by language in the menu.
    @ObservationIgnored private var externalSubtitleID: Int32?

    @ObservationIgnored private let subtitleName: String
    /// Off: the player starts with no subtitles; the viewer can still pick a track.
    @ObservationIgnored private let subtitlesOn: Bool
    @ObservationIgnored private var subtitlesTurnedOff = false

    init(url: URL, resumePosition: Double, audioURL: URL? = nil, subtitleURL: URL? = nil, subtitleName: String? = nil,
         subtitlesOn: Bool = SubtitleSettings.films) {
        self.resumePosition = resumePosition
        self.subtitleURL = subtitleURL
        self.subtitleName = subtitleName ?? "Subtitles"
        self.subtitlesOn = subtitlesOn
        // Not in VLCKit's headers; the VLC app sets the size the same way.
        let fontSize = NSSelectorFromString("setTextRendererFontSize:")
        if player.responds(to: fontSize) { player.perform(fontSize, with: NSNumber(value: SubtitleSettings.size.relativeSize)) }
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
            player.currentVideoSubTitleIndex = subtitlesOn ? track.id : -1
        }
        // The file's own default track, once VLC lists it.
        if !subtitlesOn && !subtitlesTurnedOff && player.isPlaying && subtitleTracks.contains(where: { $0.id >= 0 }) {
            subtitlesTurnedOff = true
            player.currentVideoSubTitleIndex = -1
        }
        seconds = max(0, Double(player.time.intValue) / 1000)
        duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
        playing = player.isPlaying
        buffering = !userPaused && (player.state == .opening || (player.state == .buffering && !player.isPlaying))
        if player.state == .error { failure = L("This file could not be played. Try another release.") }
        ended = player.state == .ended
        if !didResume && duration > 0 && player.isSeekable {
            didResume = true
            if resumePosition > 0 { seek(to: resumePosition) }
        }
    }
    func pause() { player.pause(); playing = false; userPaused = true; buffering = false }
    func play() { userPaused = false; player.play() }
    func toggle() { if player.isPlaying { pause() } else { play() } }
    func seek(by offset: Double) { seek(to: seconds + offset) }
    func seek(to value: Double) {
        guard duration > 0, player.isSeekable else { return }
        guard value.isFinite else { return }
        seconds = max(0, min(duration - 1, value))
        player.time = VLCTime(int: Int32(min(Double(Int32.max), seconds * 1000)))
    }
    /// VLC stops in the background, and freeing a player that is still
    /// stopping waits for that - while VLC's shutdown needs the main thread.
    /// Done on the main thread, the app froze between episodes (Apple TV).
    /// So: stop here, wait until VLC says it stopped, detach the view, and
    /// free the player on this queue; the view is let go on the main thread.
    private static let stopQueue = DispatchQueue(label: "TorrentTube.vlc-stop", qos: .userInitiated)
    func stop() {
        var stopping: StoppingPlayer? = StoppingPlayer(player: player, view: player.drawable)
        Self.stopQueue.async {
            guard let current = stopping else { return }
            current.player.stop()
            for _ in 0..<100 where current.player.state != .stopped { Thread.sleep(forTimeInterval: 0.05) }
            current.player.drawable = nil
            let view = ViewToRelease(view: current.view)
            DispatchQueue.main.async { _ = view }
            stopping = nil  // the player is freed here, off the main thread
        }
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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        controller.attach(to: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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

