import SwiftUI
import Observation
#if os(tvOS)
import TVVLCKit
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

    init(url: URL, resumePosition: Double, audioURL: URL? = nil, subtitleURL: URL? = nil) {
        self.resumePosition = resumePosition
        self.subtitleURL = subtitleURL
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=2500")
        if let audioURL { media.addOption(":input-slave=\(audioURL.absoluteString)") }
        player.media = media
    }
    func attach(to view: UIView) {
        player.drawable = view
        if !started {
            started = true
            player.play()
            // A separate subtitle file (trailers): shown from the start.
            if let subtitleURL { player.addPlaybackSlave(subtitleURL, type: .subtitle, enforce: true) }
        }
    }
    func refresh() {
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
    func stop() { player.stop(); player.drawable = nil }

    struct Track: Identifiable { let id: Int32; let name: String }
    var audioTracks: [Track] { tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes) }
    var subtitleTracks: [Track] { tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes) }
    private func tracks(names: [Any]?, indexes: [Any]?) -> [Track] {
        zip(names ?? [], indexes ?? []).compactMap { name, index in
            guard let number = index as? NSNumber else { return nil }
            return Track(id: number.int32Value, name: String(describing: name))
        }
    }
}

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

