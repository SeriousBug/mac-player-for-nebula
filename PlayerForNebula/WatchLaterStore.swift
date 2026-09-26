import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "WatchLater")

/// Whether episodes are in the watch later list, shared so every view showing an episode agrees on its state.
@MainActor
@Observable
final class WatchLaterStore {
    private(set) var states: [String: Bool] = [:]
    private(set) var updatingIDs: Set<String> = []
    /// Bumped on every successful change, so the watch later list can tell whether it is stale.
    private(set) var version = 0

    private var requestedIDs: Set<String> = []

    func isInWatchLater(_ episodeID: String) -> Bool? {
        states[episodeID]
    }

    /// Fetches the state of episodes that haven't been fetched yet.
    func loadStates(for episodeIDs: [String], session: NebulaSession) async {
        let missing = episodeIDs.filter { !requestedIDs.contains($0) }
        guard !missing.isEmpty else { return }
        requestedIDs.formUnion(missing)
        // The engagement endpoint paginates its results, so keep each request within one page.
        for start in stride(from: 0, to: missing.count, by: 20) {
            let chunk = Array(missing[start..<min(start + 20, missing.count)])
            do {
                let fetched = try await session.withToken { try await NebulaAPI.watchLaterStates(episodeIDs: chunk, token: $0) }
                states.merge(fetched) { current, _ in current }
            } catch {
                requestedIDs.subtract(chunk)
                logger.error("Loading watch later state failed: \(error, privacy: .public)")
            }
        }
    }

    func setInWatchLater(_ inWatchLater: Bool, episodeID: String, session: NebulaSession) async {
        updatingIDs.insert(episodeID)
        defer { updatingIDs.remove(episodeID) }
        do {
            try await session.withToken { try await NebulaAPI.setInWatchLater(inWatchLater, episodeID: episodeID, token: $0) }
            states[episodeID] = inWatchLater
            version += 1
        } catch {
            logger.error("Updating watch later failed: \(error, privacy: .public)")
        }
    }
}

struct WatchLaterButton: View {
    let episodeID: String

    @Environment(NebulaSession.self) private var session
    @Environment(WatchLaterStore.self) private var store

    var body: some View {
        let isUpdating = store.updatingIDs.contains(episodeID)
        switch store.isInWatchLater(episodeID) {
        case true?:
            Button("Remove from Watch Later", systemImage: "clock.badge.xmark") { set(false) }
                .disabled(isUpdating)
        case false?:
            Button("Add to Watch Later", systemImage: "clock.badge.plus") { set(true) }
                .disabled(isUpdating)
        case nil:
            EmptyView()
        }
    }

    private func set(_ inWatchLater: Bool) {
        Task { await store.setInWatchLater(inWatchLater, episodeID: episodeID, session: session) }
    }
}
