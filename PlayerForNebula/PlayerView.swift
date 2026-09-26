import AVKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Player")

struct PlayerView: View {
    let episode: VideoEpisode

    @Environment(NebulaSession.self) private var session
    @State private var model = PlayerModel()

    var body: some View {
        Group {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
            } else if model.isLoaded {
                AVPlayerViewRepresentable(player: model.player)
            } else {
                ProgressView()
            }
        }
        .task { await model.play(episode: episode, session: session) }
        .onDisappear { model.stop() }
    }
}

/// Wraps AppKit's AVPlayerView. SwiftUI's VideoPlayer aborts while building its view on this
/// macOS 27 build (`getSuperclassMetadata` in _AVKit_SwiftUI), and AVPlayerView has the native macOS controls anyway.
private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}

/// Playlist and segment URLs are signed with a token that expires, so when the CDN starts rejecting
/// requests the model fetches a fresh manifest and resumes from the same position.
@MainActor
@Observable
private final class PlayerModel {
    let player = AVPlayer()
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    private var episode: VideoEpisode?
    private var session: NebulaSession?
    private var lastReload = Date.distantPast
    private var lastSavedSeconds: Int?
    private var timeObserver: Any?
    private var rateObserver: Task<Void, Never>?

    func play(episode: VideoEpisode, session: NebulaSession) async {
        guard self.episode == nil else { return }
        self.episode = episode
        self.session = session
        async let item = makeItem()
        async let progress = loadProgress()
        guard let item = await item else { return }
        player.replaceCurrentItem(with: item)
        if let progress = await progress, !progress.completed, progress.value > 0 {
            lastSavedSeconds = progress.value
            await player.seek(to: CMTime(seconds: Double(progress.value), preferredTimescale: 1))
        }
        isLoaded = true
        player.play()
        observeProgress()
        await watchForAuthErrors()
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        rateObserver?.cancel()
        rateObserver = nil
        saveProgress()
    }

    private func loadProgress() async -> Progress? {
        guard let episode, let session else { return nil }
        do {
            return try await session.withToken { try await NebulaAPI.progress(episodeID: episode.id, token: $0) }
        } catch {
            logger.error("Loading progress failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Matches the web player, which saves every 15 seconds of playback and whenever playback pauses.
    private func observeProgress() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        rateObserver = Task { [weak self, player] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayer.rateDidChangeNotification, object: player) {
                guard let self else { return }
                if player.rate == 0 { saveProgress() }
            }
        }
    }

    private func saveProgress() {
        guard let episode, let session, player.currentItem?.status == .readyToPlay else { return }
        let seconds = Int(player.currentTime().seconds.rounded(.down))
        guard seconds != lastSavedSeconds else { return }
        lastSavedSeconds = seconds
        Task {
            do {
                try await session.withToken { try await NebulaAPI.saveProgress(episodeID: episode.id, seconds: seconds, token: $0) }
            } catch {
                logger.error("Saving progress failed: \(error, privacy: .public)")
            }
        }
    }

    private func makeItem() async -> AVPlayerItem? {
        guard let episode, let session else { return nil }
        do {
            let url = try await session.withToken { NebulaAPI.manifestURL(episodeID: episode.id, token: $0) }
            return AVPlayerItem(url: url)
        } catch NebulaSession.Error.signedOut {
            return nil
        } catch {
            errorMessage = "Couldn't play video: \(error.localizedDescription)"
            return nil
        }
    }

    /// Runs for the lifetime of the view's task, following item replacements.
    private func watchForAuthErrors() async {
        for await notification in NotificationCenter.default.notifications(named: AVPlayerItem.newErrorLogEntryNotification) {
            guard let item = notification.object as? AVPlayerItem, item === player.currentItem,
                  let status = item.errorLog()?.events.last?.errorStatusCode, status == 401 || status == 403
            else { continue }
            // A fresh manifest failing again right away is not an expiry problem, so don't loop on it.
            guard Date.now.timeIntervalSince(lastReload) > 30 else {
                logger.error("Playback rejected with \(status) right after reloading")
                errorMessage = "Couldn't play video: access was denied."
                return
            }
            lastReload = .now
            logger.info("Playback rejected with \(status), reloading with a fresh manifest")
            await reload(replacing: item)
        }
    }

    private func reload(replacing oldItem: AVPlayerItem) async {
        let position = oldItem.currentTime()
        let shouldPlay = player.timeControlStatus != .paused
        guard let newItem = await makeItem() else { return }
        await copyMediaSelection(from: oldItem, to: newItem)
        player.replaceCurrentItem(with: newItem)
        await player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
        if shouldPlay { player.play() }
    }

    /// Keeps the viewer's subtitle and audio choices across the reload. Options can't be shared
    /// between assets, so they're matched by language and name.
    private func copyMediaSelection(from oldItem: AVPlayerItem, to newItem: AVPlayerItem) async {
        for characteristic in [AVMediaCharacteristic.legible, .audible] {
            guard let oldGroup = try? await oldItem.asset.loadMediaSelectionGroup(for: characteristic),
                  let newGroup = try? await newItem.asset.loadMediaSelectionGroup(for: characteristic)
            else { continue }
            let selected = oldItem.currentMediaSelection.selectedMediaOption(in: oldGroup)
            let match = selected.flatMap { selected in
                newGroup.options.first {
                    $0.extendedLanguageTag == selected.extendedLanguageTag && $0.displayName == selected.displayName
                }
            }
            if selected == nil, newGroup.allowsEmptySelection {
                newItem.select(nil, in: newGroup)
            } else if let match {
                newItem.select(match, in: newGroup)
            }
        }
    }
}
