import OSLog
import SwiftUI

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "SavedEpisodes")

/// Whether podcast episodes are saved, shared so every view showing an episode agrees on its state.
@MainActor
@Observable
final class SavedEpisodesStore {
    private(set) var states: [String: Bool] = [:]
    private(set) var updatingIDs: Set<String> = []
    /// Bumped on every successful change, so the saved episodes list can tell whether it is stale.
    private(set) var version = 0

    private var requestedIDs: Set<String> = []

    func isSaved(_ episodeID: String) -> Bool? {
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
                let fetched = try await session.withToken { try await NebulaAPI.savedEpisodeStates(episodeIDs: chunk, token: $0) }
                states.merge(fetched) { current, _ in current }
            } catch {
                requestedIDs.subtract(chunk)
                logger.error("Loading saved episode state failed: \(error, privacy: .public)")
            }
        }
    }

    func setSaved(_ saved: Bool, episodeID: String, session: NebulaSession) async {
        updatingIDs.insert(episodeID)
        defer { updatingIDs.remove(episodeID) }
        do {
            try await session.withToken { try await NebulaAPI.setSaved(saved, episodeID: episodeID, token: $0) }
            states[episodeID] = saved
            version += 1
        } catch {
            logger.error("Updating saved episode failed: \(error, privacy: .public)")
        }
    }
}

struct SaveEpisodeButton: View {
    let episodeID: String

    @Environment(NebulaSession.self) private var session
    @Environment(SavedEpisodesStore.self) private var store

    var body: some View {
        let isUpdating = store.updatingIDs.contains(episodeID)
        switch store.isSaved(episodeID) {
        case true?:
            Button("Remove from Saved Episodes", systemImage: "bookmark.slash") { set(false) }
                .disabled(isUpdating)
        case false?:
            Button("Add to Saved Episodes", systemImage: "bookmark") { set(true) }
                .disabled(isUpdating)
        case nil:
            EmptyView()
        }
    }

    private func set(_ saved: Bool) {
        Task { await store.setSaved(saved, episodeID: episodeID, session: session) }
    }
}
