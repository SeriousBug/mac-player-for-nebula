import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Explore")

enum ExploreSection: String, CaseIterable {
    case videos
    case channels
    case podcasts
    case podcastEpisodes

    var title: LocalizedStringKey {
        switch self {
        case .videos: "Videos"
        case .channels: "Channels"
        case .podcasts: "Podcasts"
        case .podcastEpisodes: "Podcast Episodes"
        }
    }
}

private enum CategorySelection: Hashable {
    case everything
    case category(Category)

    var slug: String? {
        switch self {
        case .everything: nil
        case .category(let category): category.slug
        }
    }
}

struct ExploreView: View {
    @Environment(NebulaSession.self) private var session
    @AppStorage("exploreSection") private var section = ExploreSection.videos
    @State private var selection = CategorySelection.everything
    @State private var categories: [Category] = []
    @State private var categoriesError: String?

    var body: some View {
        HStack(spacing: 0) {
            categoryList
                .frame(width: 180)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $section) {
                    ForEach(ExploreSection.allCases, id: \.self) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .task { await loadCategories() }
    }

    private var navigationTitle: String {
        if case .category(let category) = selection { category.title } else { "Explore" }
    }

    private var categoryList: some View {
        List(selection: Binding { selection } set: { if let newValue = $0 { selection = newValue } }) {
            Text("Everything").tag(CategorySelection.everything)
            ForEach(categories) { category in
                Text(category.title).tag(CategorySelection.category(category))
            }
            if let categoriesError {
                VStack(alignment: .leading) {
                    Text(categoriesError)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { Task { await loadCategories() } }
                }
                .selectionDisabled()
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .videos: ExploreVideosView(category: selection.slug)
        case .channels: ExploreChannelsView(category: selection.slug)
        case .podcasts: ExplorePodcastsView(category: selection.slug)
        case .podcastEpisodes: ExplorePodcastEpisodesView(category: selection.slug)
        }
    }

    private func loadCategories() async {
        guard categories.isEmpty else { return }
        categoriesError = nil
        do {
            categories = try await session.withToken { try await NebulaAPI.categories(token: $0) }
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            logger.error("Loading categories failed: \(error, privacy: .public)")
            categoriesError = "Couldn't load categories"
        }
    }
}

private struct ExploreVideosView: View {
    let category: String?

    @Environment(NebulaSession.self) private var session
    @AppStorage("exploreVideosOrdering") private var ordering = DateOrdering.newest
    @State private var filter: Set<Exclusivity> = []
    @State private var list = PagedList<VideoEpisode>()

    private struct Query: Hashable {
        let category: String?
        let filter: Set<Exclusivity>
        let ordering: DateOrdering
    }

    var body: some View {
        let query = Query(category: category, filter: filter, ordering: ordering)
        VideoGrid(
            episodes: list.items,
            onReachEnd: { Task { await list.loadMore(session: session) } },
            header: {
                HStack(spacing: 8) {
                    ForEach(Exclusivity.allCases, id: \.self) { exclusivity in
                        FilterToggle(exclusivity.title, exclusivity: exclusivity, isOn: filter.contains(exclusivity)) {
                            filter.formSymmetricDifference([exclusivity])
                        }
                    }
                }
            },
            footer: {
                PagedListFooter(
                    list: list,
                    errorTitle: "Couldn't load videos",
                    emptyMessage: filter.isEmpty ? "No videos" : "No videos match these filters"
                )
            }
        )
        .toolbar { SortPicker(selection: $ordering) }
        .task(id: query) {
            await list.load(query, session: session) { pageURL, token in
                try await NebulaAPI.videoEpisodes(
                    category: query.category,
                    exclusivity: query.filter,
                    ordering: query.ordering,
                    pageURL: pageURL,
                    token: token
                )
            }
        }
    }
}

private struct ExploreChannelsView: View {
    let category: String?

    @Environment(NebulaSession.self) private var session
    @Environment(FollowStore.self) private var followStore
    @AppStorage("exploreChannelsOrdering") private var ordering = ExploreChannelsOrdering.newest
    @State private var list = PagedList<Channel>()

    private struct Query: Hashable {
        let category: String?
        let ordering: ExploreChannelsOrdering
    }

    var body: some View {
        let query = Query(category: category, ordering: ordering)
        CardGrid(
            items: list.items,
            minCardWidth: 180,
            maxCardWidth: 320,
            maxColumns: 6,
            onReachEnd: { Task { await list.loadMore(session: session) } },
            card: { ChannelCard(channel: $0) },
            header: { EmptyView() },
            footer: { PagedListFooter(list: list, errorTitle: "Couldn't load channels", emptyMessage: "No channels") }
        )
        .toolbar { SortPicker(selection: $ordering) }
        .task(id: query) {
            await list.load(query, session: session) { pageURL, token in
                try await NebulaAPI.videoChannels(category: query.category, ordering: query.ordering, pageURL: pageURL, token: token)
            }
        }
        .task(id: list.items.map(\.id)) {
            await followStore.loadStates(for: list.items.map(\.id), kind: .video, session: session)
        }
    }
}

private struct ExplorePodcastsView: View {
    let category: String?

    @Environment(NebulaSession.self) private var session
    @AppStorage("explorePodcastsOrdering") private var ordering = PodcastsOrdering.latestActivity
    @State private var list = PagedList<PodcastChannel>()

    private struct Query: Hashable {
        let category: String?
        let ordering: PodcastsOrdering
    }

    var body: some View {
        let query = Query(category: category, ordering: ordering)
        CardGrid(
            items: list.items,
            minCardWidth: 150,
            maxCardWidth: 240,
            maxColumns: 8,
            onReachEnd: { Task { await list.loadMore(session: session) } },
            card: { PodcastCard(podcast: $0) },
            header: { EmptyView() },
            footer: { PagedListFooter(list: list, errorTitle: "Couldn't load podcasts", emptyMessage: "No podcasts") }
        )
        .toolbar { SortPicker(selection: $ordering) }
        .task(id: query) {
            await list.load(query, session: session) { pageURL, token in
                try await NebulaAPI.podcastChannels(category: query.category, ordering: query.ordering, pageURL: pageURL, token: token)
            }
        }
    }
}

private struct ExplorePodcastEpisodesView: View {
    let category: String?

    @Environment(NebulaSession.self) private var session
    @AppStorage("explorePodcastEpisodesOrdering") private var ordering = DateOrdering.newest
    @State private var unplayedOnly = false
    @State private var list = PagedList<PodcastEpisode>()

    private struct Query: Hashable {
        let category: String?
        let ordering: DateOrdering
        let unplayedOnly: Bool
    }

    var body: some View {
        let query = Query(category: category, ordering: ordering, unplayedOnly: unplayedOnly)
        PodcastEpisodeGrid(
            episodes: list.items,
            onReachEnd: { Task { await list.loadMore(session: session) } },
            header: {
                FilterToggle("Unplayed", isOn: unplayedOnly) { unplayedOnly.toggle() }
            },
            footer: {
                PagedListFooter(
                    list: list,
                    errorTitle: "Couldn't load episodes",
                    emptyMessage: unplayedOnly ? "No unplayed episodes" : "No episodes"
                )
            }
        )
        .toolbar { SortPicker(selection: $ordering) }
        .task(id: query) {
            await list.load(query, session: session) { pageURL, token in
                try await NebulaAPI.podcastEpisodes(
                    category: query.category,
                    ordering: query.ordering,
                    unplayedOnly: query.unplayedOnly,
                    pageURL: pageURL,
                    token: token
                )
            }
        }
    }
}
