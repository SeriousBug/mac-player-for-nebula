import AVKit
import SwiftUI

struct PlayerView: View {
    let episode: VideoEpisode

    @Environment(NebulaSession.self) private var session
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else if let errorMessage {
                Text(errorMessage)
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard player == nil else { return }
        do {
            let url = try await session.withToken { NebulaAPI.manifestURL(episodeID: episode.id, token: $0) }
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            errorMessage = "Couldn't play video: \(error.localizedDescription)"
        }
    }
}
