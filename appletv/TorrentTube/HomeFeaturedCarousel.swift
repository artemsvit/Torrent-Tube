import SwiftUI
import Observation

/// Inline previews are separate from movie sessions and viewing history.
@MainActor @Observable
final class HomeTrailerPreview {
    var controller: EmbeddedPlayer?
    var loading = false
    var error: String?
    var muted = true
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func start(item: MediaItem, details: Details?, api: TorrentTubeAPI) {
        stop()
        error = nil; loading = true; muted = true
        let operation = generation
        preparation = Task {
            do {
                guard let trailer = try await TrailerChoice.find(title: details?.title ?? item.displayTitle,
                                                                  year: details?.year, known: details?.trailers ?? [], api: api) else {
                    throw APIError(message: L("No trailer is available for this title."))
                }
                let stream: TrailerStreamResponse = try await api.post("api/trailer/stream", body: ["key": trailer.key])
                try Task.checkCancellation()
                guard generation == operation else { return }
                let audio = try stream.audioUrl.map { try api.mediaURL($0) }
                let player = EmbeddedPlayer(url: try api.mediaURL(stream.url), resumePosition: 0, audioURL: audio)
                player.player.audio?.isMuted = true
                controller = player; loading = false
                polling = Task {
                    while !Task.isCancelled && generation == operation {
                        player.refresh()
                        if player.ended || player.failure != nil {
                            let failure = player.failure
                            stop(); error = failure
                            return
                        }
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    }
                }
            } catch {
                guard !Task.isCancelled, generation == operation else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }
    func toggleMute() {
        muted.toggle(); controller?.player.audio?.isMuted = muted
    }
    func stop() {
        generation = UUID()
        preparation?.cancel(); preparation = nil
        polling?.cancel(); polling = nil
        controller?.stop(); controller = nil; loading = false; error = nil
    }
}
