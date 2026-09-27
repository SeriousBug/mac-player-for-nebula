import SwiftUI

/// An infinitely scrolling grid of podcast episodes from a paginated endpoint.
struct PodcastEpisodeListView: View {
    let emptyMessage: String
    /// Changing this marks the loaded episodes as stale, so they are reloaded the next time the list appears.
    var version = 0
    let loadPage: PagedList<PodcastEpisode>.LoadPage

    @Environment(NebulaSession.self) private var session
    @State private var episodes = PagedList<PodcastEpisode>()

    var body: some View {
        PodcastEpisodeGrid(
            episodes: episodes.items,
            onReachEnd: { Task { await episodes.loadMore(session: session) } },
            header: { EmptyView() },
            footer: {
                PagedListFooter(list: episodes, errorTitle: "Couldn't load episodes", emptyMessage: emptyMessage)
            }
        )
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await episodes.reload(session: session) }
            }
            .keyboardShortcut("r")
        }
        .task(id: version) {
            await episodes.load(version, session: session, loadPage: loadPage)
        }
    }
}

struct FollowedPodcastsView: View {
    @Environment(NebulaSession.self) private var session
    @Environment(FollowStore.self) private var followStore
    @AppStorage("followedPodcastsOrdering") private var ordering = FollowedChannelsOrdering.recentlyFollowed
    @State private var podcasts = PagedList<PodcastChannel>()

    /// Follows changed on a podcast page don't show up in the loaded pages, so the follow version is part of the query.
    private struct Query: Hashable {
        let ordering: FollowedChannelsOrdering
        let followVersion: Int
    }

    var body: some View {
        let query = Query(ordering: ordering, followVersion: followStore.version)
        CardGrid(
            items: podcasts.items,
            minCardWidth: 150,
            maxCardWidth: 240,
            maxColumns: 8,
            onReachEnd: { Task { await podcasts.loadMore(session: session) } },
            card: { PodcastCard(podcast: $0) },
            header: { EmptyView() },
            footer: {
                PagedListFooter(list: podcasts, errorTitle: "Couldn't load podcasts", emptyMessage: "You don't follow any podcasts yet")
            }
        )
        .toolbar { SortPicker(selection: $ordering) }
        .task(id: query) {
            await podcasts.load(query, session: session) { pageURL, token in
                try await NebulaAPI.followedPodcasts(ordering: query.ordering, pageURL: pageURL, token: token)
            }
        }
    }
}
