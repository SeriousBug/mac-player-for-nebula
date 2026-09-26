import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Follow")

/// Follow changes made in this session, shared so every view showing a channel agrees on its state.
@MainActor
@Observable
final class FollowStore {
    private(set) var changes: [String: Bool] = [:]
    private(set) var updatingIDs: Set<String> = []
    /// Bumped on every successful change, so lists can tell whether they are stale.
    private(set) var version = 0

    func isFollowing(_ channelID: String) -> Bool? {
        changes[channelID]
    }

    func setFollowing(_ following: Bool, channelID: String, session: NebulaSession) async {
        updatingIDs.insert(channelID)
        defer { updatingIDs.remove(channelID) }
        do {
            try await session.withToken { try await NebulaAPI.setFollowing(following, channelID: channelID, token: $0) }
            changes[channelID] = following
            version += 1
        } catch {
            logger.error("Updating follow failed: \(error, privacy: .public)")
        }
    }
}
