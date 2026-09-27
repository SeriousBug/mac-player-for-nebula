import SwiftUI

struct ChannelCard: View {
    let channel: Channel
    /// Follow state to show until the follow store knows it.
    var followFallback: Bool?
    var onFollowChange: (() -> Void)?

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
                FollowButton(channelID: channel.id, fallback: followFallback, onChange: onFollowChange)
                    .controlSize(.small)
            }
        }
    }
}
