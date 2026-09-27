import OSLog
import SwiftUI

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "FollowedChannels")

struct FollowedChannelsView: View {
    @Environment(NebulaSession.self) private var session
    @Environment(FollowStore.self) private var followStore
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
                // Unfollowed channels stay in the list so an accidental unfollow can be undone.
                ChannelCard(channel: channel, followFallback: true) {
                    model.loadedVersion = followStore.version
                }
            },
            header: { EmptyView() },
            footer: { footer }
        )
        .toolbar {
            SortPicker(selection: $ordering)
        }
        .onAppear(perform: reloadIfStale)
        .onChange(of: ordering, reloadIfStale)
    }

    /// Follow changes made on a channel page don't show up in the loaded pages, so reload when returning from one.
    private func reloadIfStale() {
        guard model.ordering != ordering || model.loadedVersion != followStore.version else { return }
        Task { await model.reload(ordering: ordering, version: followStore.version, session: session) }
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

@MainActor
@Observable
private final class FollowedChannelsModel {
    private(set) var channels: [Channel] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var ordering: FollowedChannelsOrdering?
    /// The `FollowStore.version` the loaded channels reflect.
    var loadedVersion: Int?

    private var nextPage: URL?
    private var hasMore = true
    /// Bumped on every reload, so a page that was requested before it is dropped.
    private var generation = 0

    func reload(ordering: FollowedChannelsOrdering, version: Int, session: NebulaSession) async {
        self.ordering = ordering
        loadedVersion = version
        generation += 1
        channels = []
        nextPage = nil
        hasMore = true
        isLoading = false
        errorMessage = nil
        await loadMore(session: session)
    }

    func loadMore(session: NebulaSession) async {
        guard let ordering, hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let generation = generation
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
}
