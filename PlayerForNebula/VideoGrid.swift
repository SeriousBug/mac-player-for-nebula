import SwiftUI

struct ChannelRoute: Hashable {
    let slug: String
}

struct VideoGrid<Header: View, Footer: View>: View {
    let episodes: [VideoEpisode]
    var showsChannel = true
    /// Called when the last video scrolls into view.
    var onReachEnd: (() -> Void)?
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    @Environment(NebulaSession.self) private var session
    @Environment(WatchLaterStore.self) private var watchLaterStore

    var body: some View {
        CardGrid(
            items: episodes,
            minCardWidth: 260,
            maxCardWidth: 480,
            maxColumns: 3,
            onReachEnd: onReachEnd,
            card: { VideoCard(episode: $0, showsChannel: showsChannel) },
            header: { header },
            footer: { footer }
        )
        .task(id: episodes.map(\.id)) {
            await watchLaterStore.loadStates(for: episodes.map(\.id), session: session)
        }
    }
}

struct CardGrid<Item: Identifiable, Card: View, Header: View, Footer: View>: View {
    let items: [Item]
    let minCardWidth: CGFloat
    let maxCardWidth: CGFloat
    let maxColumns: Int
    /// Called when the last item scrolls into view.
    var onReachEnd: (() -> Void)?
    @ViewBuilder var card: (Item) -> Card
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    private let spacing: CGFloat = 20

    @State private var columnCount = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columnCount),
                    spacing: 28
                ) {
                    ForEach(items) { item in
                        card(item)
                            .onAppear {
                                if item.id == items.last?.id { onReachEnd?() }
                            }
                    }
                }
                footer
            }
            .frame(maxWidth: CGFloat(maxColumns) * maxCardWidth + CGFloat(maxColumns - 1) * spacing)
            .padding(spacing)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let fitting = Int((width - spacing) / (minCardWidth + spacing))
            columnCount = min(maxColumns, max(1, fitting))
        }
    }
}

extension VideoGrid where Header == EmptyView, Footer == EmptyView {
    init(episodes: [VideoEpisode]) {
        self.init(episodes: episodes, header: { EmptyView() }, footer: { EmptyView() })
    }
}

private struct VideoCard: View {
    let episode: VideoEpisode
    let showsChannel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: episode) {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnail
                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                if showsChannel {
                    NavigationLink(value: ChannelRoute(slug: episode.channelSlug)) {
                        HStack(spacing: 6) {
                            if let avatar = episode.images.channelAvatar {
                                AsyncImage(url: avatar.url(width: 64)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(.quaternary)
                                }
                                .frame(width: 20, height: 20)
                                .clipShape(.circle)
                            }
                            Text(episode.channelTitle)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(episode.publishedAt, format: .dateTime.day().month().year())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .contextMenu {
            WatchLaterButton(episodeID: episode.id)
        }
    }

    private var thumbnail: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: episode.images.thumbnail.url(width: 960)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    EmptyView()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    if let exclusivity = episode.exclusivity {
                        ExclusivityIcon(exclusivity: exclusivity, size: 13)
                    }
                    Text(Duration.seconds(episode.duration), format: .time(pattern: episode.duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                .padding(6)
            }
            .clipShape(.rect(cornerRadius: 8))
    }
}
