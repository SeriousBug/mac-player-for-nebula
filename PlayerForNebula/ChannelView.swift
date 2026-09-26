import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Channel")

struct ChannelView: View {
    let slug: String

    @Environment(NebulaSession.self) private var session
    @State private var model = ChannelModel()

    var body: some View {
        Group {
            if let channel = model.channel {
                VideoGrid(
                    episodes: model.episodes,
                    showsChannel: false,
                    onReachEnd: { Task { await model.loadMore(session: session) } },
                    header: { ChannelHeader(channel: channel, model: model) },
                    footer: { footer }
                )
            } else if let errorMessage = model.errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Try Again") { Task { await model.load(slug: slug, session: session) } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.channel?.title ?? "")
        .task { await model.load(slug: slug, session: session) }
    }

    @ViewBuilder private var footer: some View {
        if model.isLoadingEpisodes {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = model.episodesErrorMessage {
            VStack {
                Text(errorMessage)
                Button("Try Again") { Task { await model.loadMore(session: session) } }
            }
            .frame(maxWidth: .infinity)
        } else if model.episodes.isEmpty {
            Text("No videos")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ChannelHeader: View {
    let channel: Channel
    let model: ChannelModel

    @Environment(NebulaSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let banner = channel.images.banner {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(6, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: banner.url(width: 2560)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            EmptyView()
                        }
                    }
                    .clipShape(.rect(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                if let avatar = channel.images.avatar {
                    AsyncImage(url: avatar.url(width: 128)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.quaternary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(.circle)
                }
                Text(channel.title)
                    .font(.title.bold())
                Spacer()
                followButton
            }

            if !channel.description.isEmpty {
                Text(channel.description)
                    .textSelection(.enabled)
            }

            if !channel.links.isEmpty {
                HStack(spacing: 8) {
                    ForEach(channel.links) { link in
                        Link(destination: link.url) {
                            Label(link.title, systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .help(link.url.absoluteString)
                    }
                }
            }

            if !channel.exclusivity.isEmpty {
                HStack(spacing: 8) {
                    ForEach(channel.exclusivity, id: \.self) { exclusivity in
                        FilterToggle(exclusivity: exclusivity, isOn: model.filter.contains(exclusivity)) {
                            Task { await model.toggleFilter(exclusivity, session: session) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var followButton: some View {
        if let isFollowing = model.isFollowing {
            if isFollowing {
                Button("Following", systemImage: "checkmark") {
                    Task { await model.setFollowing(false, session: session) }
                }
                .buttonStyle(.bordered)
                .disabled(model.isUpdatingFollow)
            } else {
                Button("Follow", systemImage: "plus") {
                    Task { await model.setFollowing(true, session: session) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isUpdatingFollow)
            }
        }
    }
}

private struct FilterToggle: View {
    let exclusivity: Exclusivity
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ExclusivityIcon(exclusivity: exclusivity, size: 12)
                Text(exclusivity.title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

@MainActor
@Observable
private final class ChannelModel {
    private(set) var channel: Channel?
    private(set) var errorMessage: String?
    private(set) var isFollowing: Bool?
    private(set) var isUpdatingFollow = false

    private(set) var episodes: [VideoEpisode] = []
    private(set) var filter: Set<Exclusivity> = []
    private(set) var isLoadingEpisodes = false
    private(set) var episodesErrorMessage: String?
    private var nextPage: URL?
    private var hasMore = true
    /// Bumped whenever the filter changes, so a page that was requested for the old filter is dropped.
    private var generation = 0

    func load(slug: String, session: NebulaSession) async {
        guard channel == nil else { return }
        errorMessage = nil
        do {
            let channel = try await session.withToken { try await NebulaAPI.channel(slug: slug, token: $0) }
            self.channel = channel
            async let following: Void = loadFollowing(channelID: channel.id, session: session)
            async let episodes: Void = loadMore(session: session)
            _ = await (following, episodes)
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            logger.error("Loading channel \(slug, privacy: .public) failed: \(error, privacy: .public)")
            errorMessage = "Couldn't load channel: \(error.localizedDescription)"
        }
    }

    func loadMore(session: NebulaSession) async {
        guard let channel, hasMore, !isLoadingEpisodes else { return }
        isLoadingEpisodes = true
        episodesErrorMessage = nil
        let generation = generation
        let filter = filter
        let pageURL = nextPage
        defer {
            if generation == self.generation { isLoadingEpisodes = false }
        }
        do {
            let page = try await session.withToken {
                try await NebulaAPI.channelEpisodes(channelID: channel.id, exclusivity: filter, pageURL: pageURL, token: $0)
            }
            guard generation == self.generation else { return }
            episodes += page.results
            nextPage = page.next
            hasMore = page.next != nil
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            guard generation == self.generation else { return }
            logger.error("Loading episodes failed: \(error, privacy: .public)")
            episodesErrorMessage = "Couldn't load videos: \(error.localizedDescription)"
        }
    }

    func toggleFilter(_ exclusivity: Exclusivity, session: NebulaSession) async {
        filter.formSymmetricDifference([exclusivity])
        generation += 1
        episodes = []
        nextPage = nil
        hasMore = true
        isLoadingEpisodes = false
        await loadMore(session: session)
    }

    func setFollowing(_ following: Bool, session: NebulaSession) async {
        guard let channel else { return }
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        do {
            try await session.withToken { try await NebulaAPI.setFollowing(following, channelID: channel.id, token: $0) }
            isFollowing = following
        } catch {
            logger.error("Updating follow failed: \(error, privacy: .public)")
        }
    }

    private func loadFollowing(channelID: String, session: NebulaSession) async {
        do {
            isFollowing = try await session.withToken { try await NebulaAPI.isFollowing(channelID: channelID, token: $0) }
        } catch {
            logger.error("Loading follow state failed: \(error, privacy: .public)")
        }
    }
}
