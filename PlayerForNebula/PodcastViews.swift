import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Podcast")

struct PodcastRoute: Hashable {
    let slug: String
}

struct PodcastCard: View {
    let podcast: PodcastChannel

    var body: some View {
        NavigationLink(value: PodcastRoute(slug: podcast.slug)) {
            VStack(alignment: .leading, spacing: 6) {
                PodcastArtwork(image: podcast.images.avatar, width: 480)
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let creator = podcast.creator {
                    Text(creator)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PodcastEpisodeRow: View {
    let episode: PodcastEpisode
    var showsChannel = true

    var body: some View {
        NavigationLink(value: episode) {
            HStack(alignment: .top, spacing: 12) {
                PodcastArtwork(image: episode.images.avatar ?? episode.images.channelAvatar, width: 160)
                    .frame(width: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if showsChannel {
                            Text("\(episode.channelTitle) · \(episode.publishedAt, format: .dateTime.day().month().year())")
                        } else {
                            Text(episode.publishedAt, format: .dateTime.day().month().year())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let description = episode.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(Duration.seconds(episode.duration), format: .units(allowed: [.hours, .minutes], width: .narrow))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            SaveEpisodeButton(episodeID: episode.id)
        }
    }
}

struct PodcastArtwork: View {
    let image: NebulaImage?
    let width: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    AsyncImage(url: image.url(width: width)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        EmptyView()
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 8))
    }
}

/// A grid of podcast episodes, sized so several fit side by side on wide windows.
struct PodcastEpisodeGrid<Header: View, Footer: View>: View {
    let episodes: [PodcastEpisode]
    var showsChannel = true
    var onReachEnd: (() -> Void)?
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    @Environment(NebulaSession.self) private var session
    @Environment(SavedEpisodesStore.self) private var savedEpisodesStore

    var body: some View {
        CardGrid(
            items: episodes,
            minCardWidth: 320,
            maxCardWidth: 480,
            maxColumns: 4,
            onReachEnd: onReachEnd,
            card: { PodcastEpisodeRow(episode: $0, showsChannel: showsChannel) },
            header: { header },
            footer: { footer }
        )
        .task(id: episodes.map(\.id)) {
            await savedEpisodesStore.loadStates(for: episodes.map(\.id), session: session)
        }
    }
}

struct PodcastView: View {
    let slug: String

    @Environment(NebulaSession.self) private var session
    @Environment(FollowStore.self) private var followStore
    @AppStorage("podcastEpisodesOrdering") private var ordering = DateOrdering.newest
    @State private var podcast: PodcastChannel?
    @State private var errorMessage: String?
    @State private var unplayedOnly = false
    @State private var episodes = PagedList<PodcastEpisode>()

    private struct Query: Hashable {
        let ordering: DateOrdering
        let unplayedOnly: Bool
    }

    var body: some View {
        Group {
            if let podcast {
                PodcastEpisodeGrid(
                    episodes: episodes.items,
                    showsChannel: false,
                    onReachEnd: { Task { await episodes.loadMore(session: session) } },
                    header: { header(podcast) },
                    footer: {
                        PagedListFooter(
                            list: episodes,
                            errorTitle: "Couldn't load episodes",
                            emptyMessage: unplayedOnly ? "No unplayed episodes" : "No episodes"
                        )
                    }
                )
                .toolbar { SortPicker(selection: $ordering) }
                .task(id: Query(ordering: ordering, unplayedOnly: unplayedOnly)) {
                    await episodes.load(Query(ordering: ordering, unplayedOnly: unplayedOnly), session: session) {
                        [ordering, unplayedOnly] pageURL, token in
                        try await NebulaAPI.podcastChannelEpisodes(
                            channelID: podcast.id,
                            ordering: ordering,
                            unplayedOnly: unplayedOnly,
                            pageURL: pageURL,
                            token: token
                        )
                    }
                }
            } else if let errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(podcast?.title ?? "")
        .task { await load() }
    }

    private func header(_ podcast: PodcastChannel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                PodcastArtwork(image: podcast.images.avatar, width: 480)
                    .frame(width: 180)
                VStack(alignment: .leading, spacing: 8) {
                    Text(podcast.title)
                        .font(.title.bold())
                    if let creator = podcast.creator {
                        Text(creator)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    if let genre = podcast.genre {
                        Text(genre)
                            .foregroundStyle(.secondary)
                    }
                    if let description = podcast.description, !description.isEmpty {
                        Text(description)
                            .textSelection(.enabled)
                    }
                    FollowButton(channelID: podcast.id, kind: .podcast)
                }
            }
            FilterToggle("Unplayed", isOn: unplayedOnly) { unplayedOnly.toggle() }
        }
    }

    private func load() async {
        guard podcast == nil else { return }
        errorMessage = nil
        do {
            let podcast = try await session.withToken { try await NebulaAPI.podcastChannel(slug: slug, token: $0) }
            self.podcast = podcast
            await followStore.loadStates(for: [podcast.id], kind: .podcast, session: session)
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            logger.error("Loading podcast \(slug, privacy: .public) failed: \(error, privacy: .public)")
            errorMessage = "Couldn't load podcast: \(error.localizedDescription)"
        }
    }
}
