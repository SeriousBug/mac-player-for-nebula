import AVKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "PodcastPlayer")

struct PodcastPlayerView: View {
    let episode: PodcastEpisode

    @Environment(NebulaSession.self) private var session
    @Environment(SavedEpisodesStore.self) private var savedEpisodesStore
    @State private var model = PodcastPlayerModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PodcastArtwork(image: episode.images.avatar ?? episode.images.channelAvatar, width: 640)
                    .frame(width: 280)
                VStack(spacing: 6) {
                    Text(episode.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    NavigationLink(episode.channelTitle, value: PodcastRoute(slug: episode.channelSlug))
                        .buttonStyle(.link)
                    Text(episode.publishedAt, format: .dateTime.day().month().year())
                        .foregroundStyle(.secondary)
                }
                AVPlayerViewRepresentable(player: model.player, controlsStyle: .inline)
                    .frame(height: 64)
                if let description = episode.description {
                    Text(description)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 640)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            SaveEpisodeButton(episodeID: episode.id)
        }
        .task { await savedEpisodesStore.loadStates(for: [episode.id], session: session) }
        .task { await model.play(episode: episode, session: session) }
        .onDisappear { model.stop() }
    }
}

@MainActor
@Observable
private final class PodcastPlayerModel {
    let player = AVPlayer()

    private var didStart = false
    private var progressTracker: ProgressTracker?

    func play(episode: PodcastEpisode, session: NebulaSession) async {
        guard !didStart else { return }
        didStart = true
        player.replaceCurrentItem(with: AVPlayerItem(url: episode.audioURL))
        let resumeSeconds: Int?
        do {
            resumeSeconds = try await session.withToken {
                try await NebulaAPI.podcastProgress(episodeID: episode.id, token: $0)
            }?.resumeSeconds
        } catch {
            logger.error("Loading progress failed: \(error, privacy: .public)")
            resumeSeconds = nil
        }
        if let resumeSeconds {
            await player.seek(to: CMTime(seconds: Double(resumeSeconds), preferredTimescale: 1))
        }
        player.play()
        progressTracker = ProgressTracker(player: player, savedSeconds: resumeSeconds) { seconds in
            try await session.withToken {
                try await NebulaAPI.savePodcastProgress(episodeID: episode.id, seconds: seconds, token: $0)
            }
        }
    }

    func stop() {
        player.pause()
        progressTracker?.stop()
        progressTracker = nil
    }
}
