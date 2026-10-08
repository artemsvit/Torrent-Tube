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
                    ArtworkView(url: trailer.thumbnailURL, background: true, fill: true)
                        .ignoresSafeArea()
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.88), location: 0),
                            .init(color: .black.opacity(0.6), location: 0.5),
                            .init(color: .black.opacity(0.88), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    VStack(spacing: 36) {
                        Text(trailer.name)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
                        if let error {
                            VStack(spacing: 24) {
                                HStack(spacing: 14) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.system(size: 26, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                )
                                HStack(spacing: 24) {
                                    Button {
                                        Task { await prepare() }
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
                        } else {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.4)
                                .padding(.vertical, 10)

                            Button(action: close) {
                                Label(L("Back"), systemImage: "arrow.backward")
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.25))
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(70)
                    .frame(maxWidth: 1100)
                }
                .background(.black)
                .ignoresSafeArea()
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
