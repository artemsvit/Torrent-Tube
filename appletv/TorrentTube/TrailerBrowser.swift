import SwiftUI

struct TrailerPlayer: View {
    let trailer: Trailer
    let api: TorrentTubeAPI
    @Environment(\.dismiss) private var dismiss
    @State private var controller: EmbeddedPlayer?
    @State private var error: String?
    var body: some View {
        Group {
            if let controller {
                PlayerView(controller: controller, title: trailer.name, streamStatus: nil) { close() }
                    .task {
                        while !Task.isCancelled {
                            controller.refresh()
                            if controller.ended { close(); return }
                            do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        }
                    }
            } else {
                ZStack {
                    ArtworkView(url: trailer.thumbnailURL, background: true)
                    Color.black.opacity(0.8)
                    VStack(spacing: 30) {
                        Text(trailer.name).font(.system(size: 38, weight: .bold)).multilineTextAlignment(.center)
                        if let error { ErrorPanel(message: error) { Task { await prepare() } } }
                        else { ProgressView(L("Preparing trailer…")) }
                        Button(L("Back")) { close() }
                    }.padding(70).frame(maxWidth: 1100)
                }.background(.black)
            }
        }
        .task { await prepare() }
        .onExitCommand { close() }
        .onDisappear { controller?.stop() }
    }
    private func prepare() async {
        guard controller == nil else { return }
        error = nil
        do {
            // Subtitles in the app's language: Ukrainian when YouTube gives them, else English.
            let subtitles = Localizer.shared.language == .uk ? "uk,en" : "en"
            let stream: TrailerStreamResponse = try await api.post("api/trailer/stream", body: ["key": trailer.key, "subtitles": subtitles])
            try Task.checkCancellation()
            let audio = try stream.audioUrl.map { try api.mediaURL($0) }
            let subtitleURL = try stream.subtitleUrl.map { try api.mediaURL($0) }
            controller = EmbeddedPlayer(url: try api.mediaURL(stream.url), resumePosition: 0, audioURL: audio, subtitleURL: subtitleURL, subtitleName: stream.subtitleName)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func close() { controller?.stop(); dismiss() }
}
