import SwiftUI

struct VideoGrid: View {
    let episodes: [VideoEpisode]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20, alignment: .top)], spacing: 28) {
                ForEach(episodes) { episode in
                    VideoCard(episode: episode)
                }
            }
            .padding(20)
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
                    AsyncImage(url: episode.images.thumbnail.url(width: 720)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        EmptyView()
                    }
                }
                .clipShape(.rect(cornerRadius: 8))

            Text(episode.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
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
