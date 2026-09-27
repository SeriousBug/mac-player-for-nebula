import AVKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "Player")

struct PlayerView: View {
    let episode: VideoEpisode

    @Environment(NebulaSession.self) private var session
    @Environment(WatchLaterStore.self) private var watchLaterStore
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
        .toolbar {
            WatchLaterButton(episodeID: episode.id)
        }
        .task { await watchLaterStore.loadStates(for: [episode.id], session: session) }
        .task { await model.play(episode: episode, session: session) }
        .onDisappear { model.stop() }
    }
}

/// Wraps AppKit's AVPlayerView. SwiftUI's VideoPlayer aborts while building its view on this
/// macOS 27 build (`getSuperclassMetadata` in _AVKit_SwiftUI), and AVPlayerView has the native macOS controls anyway.
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer
    var controlsStyle = AVPlayerViewControlsStyle.floating

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = controlsStyle
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
    private var progressTracker: ProgressTracker?

    func play(episode: VideoEpisode, session: NebulaSession) async {
        guard self.episode == nil else { return }
        self.episode = episode
        self.session = session
        async let item = makeItem()
        async let progress = loadProgress()
        guard let item = await item else { return }
        player.replaceCurrentItem(with: item)
        let resumeSeconds = await progress?.resumeSeconds
        if let resumeSeconds {
            await player.seek(to: CMTime(seconds: Double(resumeSeconds), preferredTimescale: 1))
        }
        isLoaded = true
        player.play()
        progressTracker = ProgressTracker(player: player, savedSeconds: resumeSeconds) { seconds in
            try await session.withToken { try await NebulaAPI.saveProgress(episodeID: episode.id, seconds: seconds, token: $0) }
        }
        await watchForAuthErrors()
    }

    func stop() {
        player.pause()
        progressTracker?.stop()
        progressTracker = nil
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

/// Saves the playback position like the web player, every 15 seconds of playback and whenever playback pauses.
@MainActor
final class ProgressTracker {
    typealias Save = (_ seconds: Int) async throws -> Void

    private let player: AVPlayer
    private let save: Save
    private var savedSeconds: Int?
    private var timeObserver: Any?
    private var rateObserver: Task<Void, Never>?

    init(player: AVPlayer, savedSeconds: Int?, save: @escaping Save) {
        self.player = player
        self.savedSeconds = savedSeconds
        self.save = save
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        rateObserver = Task { [weak self, player] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayer.rateDidChangeNotification, object: player) {
                guard let self else { return }
                if player.rate == 0 { saveNow() }
            }
        }
    }

    func stop() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        rateObserver?.cancel()
        rateObserver = nil
        saveNow()
    }

    private func saveNow() {
        guard player.currentItem?.status == .readyToPlay else { return }
        let seconds = Int(player.currentTime().seconds.rounded(.down))
        guard seconds != savedSeconds else { return }
        savedSeconds = seconds
        Task {
            do {
                try await save(seconds)
            } catch {
                logger.error("Saving progress failed: \(error, privacy: .public)")
            }
        }
    }
}
