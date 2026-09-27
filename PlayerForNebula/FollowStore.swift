import OSLog
import SwiftUI

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "Follow")

/// Whether channels are followed, shared so every view showing a channel agrees on its state.
@MainActor
@Observable
final class FollowStore {
    private(set) var states: [String: Bool] = [:]
    private(set) var updatingIDs: Set<String> = []
    /// Bumped on every successful change, so lists can tell whether they are stale.
    private(set) var version = 0

    private var requestedIDs: Set<String> = []

    func isFollowing(_ channelID: String) -> Bool? {
        states[channelID]
    }

    /// Fetches the state of channels that haven't been fetched yet.
    func loadStates(for channelIDs: [String], kind: ChannelKind, session: NebulaSession) async {
        let missing = channelIDs.filter { !requestedIDs.contains($0) }
        guard !missing.isEmpty else { return }
        requestedIDs.formUnion(missing)
        // The engagement endpoint paginates its results, so keep each request within one page.
        for start in stride(from: 0, to: missing.count, by: 20) {
            let chunk = Array(missing[start..<min(start + 20, missing.count)])
            do {
                let fetched = try await session.withToken {
                    try await NebulaAPI.followStates(channelIDs: chunk, kind: kind, token: $0)
                }
                states.merge(fetched) { current, _ in current }
            } catch {
                requestedIDs.subtract(chunk)
                logger.error("Loading follow state failed: \(error, privacy: .public)")
            }
        }
    }

    func setFollowing(_ following: Bool, channelID: String, kind: ChannelKind = .video, session: NebulaSession) async {
        updatingIDs.insert(channelID)
        defer { updatingIDs.remove(channelID) }
        do {
            try await session.withToken {
                try await NebulaAPI.setFollowing(following, channelID: channelID, kind: kind, token: $0)
            }
            states[channelID] = following
            version += 1
        } catch {
            logger.error("Updating follow failed: \(error, privacy: .public)")
        }
    }
}

struct FollowButton: View {
    let channelID: String
    var kind = ChannelKind.video
    /// Used until the store knows the state. Nothing is shown while both are unknown.
    var fallback: Bool?
    var onChange: (() -> Void)?

    @Environment(NebulaSession.self) private var session
    @Environment(FollowStore.self) private var store

    var body: some View {
        let isUpdating = store.updatingIDs.contains(channelID)
        switch store.isFollowing(channelID) ?? fallback {
        case true?:
            Button("Following", systemImage: "checkmark") { set(false) }
                .buttonStyle(.bordered)
                .disabled(isUpdating)
        case false?:
            Button("Follow", systemImage: "plus") { set(true) }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
        case nil:
            EmptyView()
        }
    }

    private func set(_ following: Bool) {
        Task {
            await store.setFollowing(following, channelID: channelID, kind: kind, session: session)
            onChange?()
        }
    }
}
