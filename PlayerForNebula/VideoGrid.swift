import SwiftUI

struct VideoGrid: View {
    let episodes: [VideoEpisode]

    private let minCardWidth: CGFloat = 260
    private let maxCardWidth: CGFloat = 480
    private let maxColumns = 3
    private let spacing: CGFloat = 20

    @State private var columnCount = 1

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columnCount),
                spacing: 28
            ) {
                ForEach(episodes) { episode in
                    NavigationLink(value: episode) {
                        VideoCard(episode: episode)
                    }
                    .buttonStyle(.plain)
                }
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

private struct VideoCard: View {
    let episode: VideoEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .clipShape(.rect(cornerRadius: 8))

            Text(episode.title)
                .font(.headline)
                .lineLimit(2)

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
                Spacer()
                Text(episode.publishedAt, format: .dateTime.day().month().year())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
