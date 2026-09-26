import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "FollowedChannels")

struct FollowedChannelsView: View {
    @Environment(NebulaSession.self) private var session
    @State private var model = FollowedChannelsModel()
    @AppStorage("followedChannelsOrdering") private var ordering = FollowedChannelsOrdering.recentlyFollowed

    var body: some View {
        CardGrid(
            items: model.channels,
            minCardWidth: 180,
            maxCardWidth: 320,
            maxColumns: 6,
            onReachEnd: { Task { await model.loadMore(session: session) } },
            card: { channel in
                ChannelCard(channel: channel, model: model)
            },
            header: { EmptyView() },
            footer: { footer }
        )
        .toolbar {
            Picker("Sort By", selection: $ordering) {
                ForEach(FollowedChannelsOrdering.allCases, id: \.self) { ordering in
                    Text(ordering.title).tag(ordering)
                }
            }
            .pickerStyle(.menu)
        }
        .task(id: ordering) { await model.reload(ordering: ordering, session: session) }
    }

    @ViewBuilder private var footer: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = model.errorMessage {
            VStack {
                Text(errorMessage)
                Button("Try Again") { Task { await model.loadMore(session: session) } }
            }
            .frame(maxWidth: .infinity)
        } else if model.channels.isEmpty {
            Text("You don't follow any channels yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ChannelCard: View {
    let channel: Channel
    let model: FollowedChannelsModel

    @Environment(NebulaSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: ChannelRoute(slug: channel.slug)) {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let featured = channel.images.featured {
                            AsyncImage(url: featured.url(width: 640)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                EmptyView()
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 8) {
                NavigationLink(value: ChannelRoute(slug: channel.slug)) {
                    HStack(alignment: .top, spacing: 8) {
                        if let avatar = channel.images.avatar {
                            AsyncImage(url: avatar.url(width: 64)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(.quaternary)
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(.circle)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.title)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let genre = channel.genre {
                                Text(genre)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                followButton
            }
        }
    }

    @ViewBuilder private var followButton: some View {
        let isUpdating = model.updatingIDs.contains(channel.id)
        if model.unfollowedIDs.contains(channel.id) {
            Button("Follow", systemImage: "plus") {
                Task { await model.setFollowing(true, channelID: channel.id, session: session) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isUpdating)
        } else {
            Button("Following", systemImage: "checkmark") {
                Task { await model.setFollowing(false, channelID: channel.id, session: session) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isUpdating)
        }
    }
}

@MainActor
@Observable
private final class FollowedChannelsModel {
    private(set) var channels: [Channel] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Unfollowed channels stay in the list so an accidental unfollow can be undone.
    private(set) var unfollowedIDs: Set<String> = []
    private(set) var updatingIDs: Set<String> = []

    private var ordering = FollowedChannelsOrdering.recentlyFollowed
    private var nextPage: URL?
    private var hasMore = true
    /// Bumped whenever the ordering changes, so a page that was requested for the old ordering is dropped.
    private var generation = 0

    func reload(ordering: FollowedChannelsOrdering, session: NebulaSession) async {
        self.ordering = ordering
        generation += 1
        channels = []
        unfollowedIDs = []
        nextPage = nil
        hasMore = true
        isLoading = false
        errorMessage = nil
        await loadMore(session: session)
    }

    func loadMore(session: NebulaSession) async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let generation = generation
        let ordering = ordering
        let pageURL = nextPage
        defer {
            if generation == self.generation { isLoading = false }
        }
        do {
            let page = try await session.withToken {
                try await NebulaAPI.followedChannels(ordering: ordering, pageURL: pageURL, token: $0)
            }
            guard generation == self.generation else { return }
            channels += page.results
            nextPage = page.next
            hasMore = page.next != nil
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            guard generation == self.generation else { return }
            logger.error("Loading followed channels failed: \(error, privacy: .public)")
            errorMessage = "Couldn't load channels: \(error.localizedDescription)"
        }
    }

    func setFollowing(_ following: Bool, channelID: String, session: NebulaSession) async {
        updatingIDs.insert(channelID)
        defer { updatingIDs.remove(channelID) }
        do {
            try await session.withToken { try await NebulaAPI.setFollowing(following, channelID: channelID, token: $0) }
            if following {
                unfollowedIDs.remove(channelID)
            } else {
                unfollowedIDs.insert(channelID)
            }
        } catch {
            logger.error("Updating follow failed: \(error, privacy: .public)")
        }
    }
}
