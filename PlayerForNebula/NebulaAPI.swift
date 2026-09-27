import Foundation

enum NebulaAPI {
    static let apiKeyCookieName = "nebula_auth.apiToken"

    enum Error: Swift.Error {
        case badStatus(Int, URL)
    }

    /// Exchanges the long-lived API key from login for a short-lived JWT used by the content API.
    static func authorize(apiKey: String) async throws -> String {
        struct Response: Decodable { let token: String }
        var request = URLRequest(url: URL(string: "https://users.api.nebula.app/api/v1/authorization/")!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        return try await JSONDecoder().decode(Response.self, from: send(request)).token
    }

    /// Returns the decoded episodes along with the raw response body.
    static func latestFollowedEpisodes(token: String) async throws -> ([VideoEpisode], Data) {
        struct Response: Decodable { let results: [VideoEpisode] }
        var components = URLComponents(string: "https://content.api.nebula.app/video_episodes/")!
        components.queryItems = [
            URLQueryItem(name: "following", value: "true"),
            URLQueryItem(name: "ordering", value: "-published_at"),
            URLQueryItem(name: "page_size", value: "24"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        return (try decoder.decode(Response.self, from: data).results, data)
    }

    static func channel(slug: String, token: String) async throws -> Channel {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/content/\(slug)/")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(Channel.self, from: send(request))
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func channelEpisodes(
        channelID: String,
        exclusivity: Set<Exclusivity>,
        pageURL: URL? = nil,
        token: String
    ) async throws -> EpisodePage {
        let url = pageURL ?? {
            var components = URLComponents(string: "https://content.api.nebula.app/video_channels/\(channelID)/video_episodes/")!
            components.queryItems = [
                URLQueryItem(name: "ordering", value: "-published_at"),
                URLQueryItem(name: "page_size", value: "24"),
            ] + exclusivity.map(\.rawValue).sorted().map { URLQueryItem(name: "exclusivity", value: $0) }
            return components.url!
        }()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(EpisodePage.self, from: send(request))
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func followedChannels(
        ordering: FollowedChannelsOrdering,
        pageURL: URL? = nil,
        token: String
    ) async throws -> ChannelPage {
        let url = pageURL ?? {
            var components = URLComponents(string: "https://content.api.nebula.app/video_channels/")!
            components.queryItems = [
                URLQueryItem(name: "following", value: "true"),
                URLQueryItem(name: "ordering", value: ordering.rawValue),
                URLQueryItem(name: "page_size", value: "24"),
            ]
            return components.url!
        }()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(ChannelPage.self, from: send(request))
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func watchLater(pageURL: URL? = nil, token: String) async throws -> EpisodePage {
        let url = pageURL ?? {
            var components = URLComponents(string: "https://content.api.nebula.app/user_playlists/watch-later/video_episodes/")!
            components.queryItems = [
                URLQueryItem(name: "ordering", value: "-added_to_playlist"),
                URLQueryItem(name: "page_size", value: "24"),
            ]
            return components.url!
        }()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(EpisodePage.self, from: send(request))
    }

    /// Videos the user has started, most recently watched first.
    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func watchHistory(pageURL: URL? = nil, token: String) async throws -> EpisodePage {
        let url = pageURL ?? {
            var components = URLComponents(string: "https://content.api.nebula.app/video_episodes/")!
            components.queryItems = [
                URLQueryItem(name: "progress", value: "any_progress"),
                URLQueryItem(name: "ordering", value: "-progress"),
                URLQueryItem(name: "page_size", value: "24"),
            ]
            return components.url!
        }()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(EpisodePage.self, from: send(request))
    }

    /// Video and podcast categories combined, the way the web app lists them on its explore page.
    static func categories(token: String) async throws -> [Category] {
        async let video = categories(type: "video_channel", token: token)
        async let podcast = categories(type: "podcast_channel", token: token)
        var seen: Set<String> = []
        return try await (video + podcast).filter { seen.insert($0.slug).inserted }
    }

    private static func categories(type: String, token: String) async throws -> [Category] {
        var components = URLComponents(string: "https://content.api.nebula.app/categories/")!
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "page_size", value: "100"),
        ]
        return try await page(components.url!, token: token).results
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func videoEpisodes(
        category: String?,
        exclusivity: Set<Exclusivity>,
        ordering: DateOrdering,
        pageURL: URL? = nil,
        token: String
    ) async throws -> EpisodePage {
        try await page(pageURL ?? listURL(
            "video_episodes/",
            category: category,
            ordering: ordering.rawValue,
            extra: exclusivity.map(\.rawValue).sorted().map { URLQueryItem(name: "exclusivity", value: $0) }
        ), token: token)
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func videoChannels(
        category: String?,
        ordering: ExploreChannelsOrdering,
        pageURL: URL? = nil,
        token: String
    ) async throws -> ChannelPage {
        try await page(pageURL ?? listURL("video_channels/", category: category, ordering: ordering.rawValue), token: token)
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func podcastChannels(
        category: String?,
        ordering: PodcastsOrdering,
        pageURL: URL? = nil,
        token: String
    ) async throws -> Page<PodcastChannel> {
        try await page(pageURL ?? listURL("podcast_channels/", category: category, ordering: ordering.rawValue), token: token)
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func podcastEpisodes(
        category: String?,
        ordering: DateOrdering,
        unplayedOnly: Bool,
        pageURL: URL? = nil,
        token: String
    ) async throws -> Page<PodcastEpisode> {
        try await page(pageURL ?? listURL(
            "podcast_episodes/",
            category: category,
            ordering: ordering.rawValue,
            extra: unplayedOnly ? [URLQueryItem(name: "progress", value: "unwatched")] : []
        ), token: token)
    }

    static func podcastChannel(slug: String, token: String) async throws -> PodcastChannel {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/content/\(slug)/")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(PodcastChannel.self, from: send(request))
    }

    /// Pass `page.next` from the previous result as `pageURL` to load the following page.
    static func podcastChannelEpisodes(
        channelID: String,
        ordering: DateOrdering,
        unplayedOnly: Bool,
        pageURL: URL? = nil,
        token: String
    ) async throws -> Page<PodcastEpisode> {
        try await page(pageURL ?? listURL(
            "podcast_channels/\(channelID)/podcast_episodes/",
            category: nil,
            ordering: ordering.rawValue,
            extra: unplayedOnly ? [URLQueryItem(name: "progress", value: "unwatched")] : []
        ), token: token)
    }

    static func podcastProgress(episodeID: String, token: String) async throws -> Progress? {
        struct Engagement: Decodable { let id: String; let progress: Progress? }
        struct Response: Decodable { let results: [Engagement] }
        var components = URLComponents(string: "https://content.api.nebula.app/podcast_episodes/engagement/")!
        components.queryItems = [URLQueryItem(name: "ids", value: episodeID)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await decoder.decode(Response.self, from: send(request))
        return response.results.first { $0.id == episodeID }?.progress
    }

    static func savePodcastProgress(episodeID: String, seconds: Int, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/podcast_episodes/\(episodeID)/progress/")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["value": seconds])
        _ = try await send(request)
    }

    private static func listURL(_ path: String, category: String?, ordering: String, extra: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: "https://content.api.nebula.app/\(path)")!
        components.queryItems = [
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "page_size", value: "24"),
        ] + (category.map { [URLQueryItem(name: "category", value: $0)] } ?? []) + extra
        return components.url!
    }

    private static func page<Item: Decodable>(_ url: URL, token: String) async throws -> Page<Item> {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await decoder.decode(Page<Item>.self, from: send(request))
    }

    static func isFollowing(channelID: String, token: String) async throws -> Bool {
        struct Engagement: Decodable { let id: String; let following: Bool }
        struct Response: Decodable { let results: [Engagement] }
        var components = URLComponents(string: "https://content.api.nebula.app/video_channels/engagement/")!
        components.queryItems = [URLQueryItem(name: "ids", value: channelID)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await decoder.decode(Response.self, from: send(request))
        return response.results.first { $0.id == channelID }?.following ?? false
    }

    /// Returns whether each channel is followed, keyed by channel ID.
    static func followStates(channelIDs: [String], kind: ChannelKind, token: String) async throws -> [String: Bool] {
        struct Engagement: Decodable { let id: String; let following: Bool }
        struct Response: Decodable { let results: [Engagement] }
        var components = URLComponents(string: "https://content.api.nebula.app/\(kind.pathComponent)/engagement/")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: channelIDs.joined(separator: ",")),
            URLQueryItem(name: "page_size", value: String(channelIDs.count)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await decoder.decode(Response.self, from: send(request))
        return Dictionary(response.results.map { ($0.id, $0.following) }, uniquingKeysWith: { first, _ in first })
    }

    static func setFollowing(_ following: Bool, channelID: String, kind: ChannelKind = .video, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/\(kind.pathComponent)/\(channelID)/follow/")!)
        request.httpMethod = following ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    static func progress(episodeID: String, token: String) async throws -> Progress? {
        struct Engagement: Decodable { let id: String; let progress: Progress? }
        struct Response: Decodable { let results: [Engagement] }
        var components = URLComponents(string: "https://content.api.nebula.app/video_episodes/engagement/")!
        components.queryItems = [URLQueryItem(name: "ids", value: episodeID)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await decoder.decode(Response.self, from: send(request))
        return response.results.first { $0.id == episodeID }?.progress
    }

    /// Returns whether each episode is in the watch later list, keyed by episode ID.
    static func watchLaterStates(episodeIDs: [String], token: String) async throws -> [String: Bool] {
        struct Engagement: Decodable {
            let id: String
            let watchLater: Bool

            enum CodingKeys: String, CodingKey {
                case id
                case watchLater = "watch_later"
            }
        }
        struct Response: Decodable { let results: [Engagement] }
        var components = URLComponents(string: "https://content.api.nebula.app/video_episodes/engagement/")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: episodeIDs.joined(separator: ",")),
            URLQueryItem(name: "page_size", value: String(episodeIDs.count)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await decoder.decode(Response.self, from: send(request))
        return Dictionary(response.results.map { ($0.id, $0.watchLater) }, uniquingKeysWith: { first, _ in first })
    }

    static func setInWatchLater(_ inWatchLater: Bool, episodeID: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/user_playlists/watch-later/video_episodes/")!)
        request.httpMethod = inWatchLater ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["id": episodeID])
        _ = try await send(request)
    }

    static func saveProgress(episodeID: String, seconds: Int, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/video_episodes/\(episodeID)/progress/")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["value": seconds])
        _ = try await send(request)
    }

    /// Redirects to a signed HLS playlist on starlight.nebula.tv. The content API expects the JWT
    /// in the query here because the player requests the playlist without custom headers.
    static func manifestURL(episodeID: String, token: String) -> URL {
        var components = URLComponents(string: "https://content.api.nebula.app/video_episodes/\(episodeID)/manifest.m3u8")!
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "all_manifest", value: "true"),
        ]
        return components.url!
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) { return date }
            return try Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        return decoder
    }()

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Error.badStatus(status, request.url!) }
        return data
    }
}

struct Progress: Decodable {
    /// Playback position in seconds.
    let value: Int
    let completed: Bool

    /// Where playback should pick up, or nil to start from the beginning.
    var resumeSeconds: Int? {
        !completed && value > 0 ? value : nil
    }
}

struct NebulaImage: Decodable, Hashable {
    let src: URL

    /// images.nebula.tv resizes on the server, so request a size that fits the display instead of the original.
    func url(width: Int) -> URL {
        src.appending(queryItems: [URLQueryItem(name: "width", value: String(width))])
    }
}

enum Exclusivity: String, Decodable, CaseIterable {
    case original, plus, first

    var title: String {
        switch self {
        case .original: "Original"
        case .plus: "Plus"
        case .first: "First"
        }
    }
}

struct VideoEpisode: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let channelTitle: String
    let channelSlug: String
    let publishedAt: Date
    let duration: Int
    let attributes: [String]
    let images: Images

    /// The web app shows a single badge per video.
    var exclusivity: Exclusivity? {
        if attributes.contains("is_nebula_first") { return .first }
        if attributes.contains("is_nebula_plus") { return .plus }
        if attributes.contains("is_nebula_original") { return .original }
        return nil
    }

    struct Images: Decodable, Hashable {
        let thumbnail: NebulaImage
        let channelAvatar: NebulaImage?

        enum CodingKeys: String, CodingKey {
            case thumbnail
            case channelAvatar = "channel_avatar"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, images, duration, attributes
        case channelTitle = "channel_title"
        case channelSlug = "channel_slug"
        case publishedAt = "published_at"
    }
}

struct Page<Item: Decodable>: Decodable {
    let results: [Item]
    let next: URL?
}

extension Page: Sendable where Item: Sendable {}

typealias EpisodePage = Page<VideoEpisode>

enum FollowedChannelsOrdering: String, CaseIterable {
    case recentlyFollowed = "-follow"
    case latestActivity = "-episode_published"
    case alphabetical = "title"

    var title: String {
        switch self {
        case .recentlyFollowed: "Recently Followed"
        case .latestActivity: "Latest Activity"
        case .alphabetical: "Alphabetical"
        }
    }
}

typealias ChannelPage = Page<Channel>

struct Channel: Decodable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let genre: String?
    let exclusivity: [Exclusivity]
    let images: Images
    let links: [Link]

    struct Images: Decodable {
        let avatar: NebulaImage?
        let banner: NebulaImage?
        let featured: NebulaImage?
    }

    struct Link: Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, description, exclusivity, images
        case genre = "genre_category_title"
        case twitter, bluesky, instagram, facebook, reddit, patreon, website, merch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        // Unknown values would fail the whole channel, and the filter can't be offered for them anyway.
        exclusivity = (try container.decodeIfPresent([String].self, forKey: .exclusivity) ?? []).compactMap(Exclusivity.init)
        images = try container.decode(Images.self, forKey: .images)
        let linkKeys: [(CodingKeys, String)] = [
            (.twitter, "Twitter"), (.bluesky, "Bluesky"), (.instagram, "Instagram"), (.facebook, "Facebook"),
            (.reddit, "Reddit"), (.patreon, "Patreon"), (.website, "Website"), (.merch, "Store"),
        ]
        links = try linkKeys.compactMap { key, title in
            guard let string = try container.decodeIfPresent(String.self, forKey: key),
                  let url = URL(string: string), url.scheme?.hasPrefix("http") == true
            else { return nil }
            return Link(title: title, url: url)
        }
    }
}

enum ChannelKind {
    case video, podcast

    var pathComponent: String {
        switch self {
        case .video: "video_channels"
        case .podcast: "podcast_channels"
        }
    }
}

struct Category: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
}

enum DateOrdering: String, CaseIterable {
    case newest = "-published_at"
    case oldest = "published_at"

    var title: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
}

enum ExploreChannelsOrdering: String, CaseIterable {
    case newest = "-published_at"
    case latestActivity = "-episode_published"
    case alphabetical = "title"

    var title: String {
        switch self {
        case .newest: "Newest"
        case .latestActivity: "Latest Activity"
        case .alphabetical: "Alphabetical"
        }
    }
}

enum PodcastsOrdering: String, CaseIterable {
    case latestActivity = "-episode_published"
    case newest = "-published_at"
    case alphabetical = "title"

    var title: String {
        switch self {
        case .latestActivity: "Latest Activity"
        case .newest: "Newest"
        case .alphabetical: "Alphabetical"
        }
    }
}

struct PodcastChannel: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let creator: String?
    let description: String?
    let genre: String?
    let images: Images

    struct Images: Decodable, Hashable {
        let avatar: NebulaImage?
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, title, creator, description, images
        case genre = "genre_category_title"
    }
}

struct PodcastEpisode: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let channelTitle: String
    let channelSlug: String
    let publishedAt: Date
    let duration: Int
    /// A plain audio file on the podcast host, which the web player streams directly.
    let audioURL: URL
    let images: Images

    struct Images: Decodable, Hashable {
        let avatar: NebulaImage?
        let channelAvatar: NebulaImage?

        enum CodingKeys: String, CodingKey {
            case avatar
            case channelAvatar = "channel_avatar"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, duration, images
        case channelTitle = "channel_title"
        case channelSlug = "channel_slug"
        case publishedAt = "published_at"
        case audioURL = "episode_url"
    }
}

/// Describes the shape of a JSON value, keeping one example per array, for logging.
func jsonStructure(_ data: Data) -> String {
    func describe(_ value: Any, _ indent: String) -> String {
        switch value {
        case let dict as [String: Any]:
            let fields = dict.keys.sorted().map { "\(indent)  \($0): \(describe(dict[$0]!, indent + "  "))" }
            return "{\n" + fields.joined(separator: "\n") + "\n\(indent)}"
        case let array as [Any]:
            guard let first = array.first else { return "[]" }
            return "[\(array.count)× " + describe(first, indent) + "]"
        case is NSNull:
            return "null"
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number"
        default:
            return "string"
        }
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) else { return "<invalid JSON>" }
    return describe(object, "")
}
