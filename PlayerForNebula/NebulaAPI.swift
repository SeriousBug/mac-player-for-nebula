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

    static func setFollowing(_ following: Bool, channelID: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://content.api.nebula.app/video_channels/\(channelID)/follow/")!)
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

struct EpisodePage: Decodable {
    let results: [VideoEpisode]
    let next: URL?
}

struct Channel: Decodable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let exclusivity: [Exclusivity]
    let images: Images
    let links: [Link]

    struct Images: Decodable {
        let avatar: NebulaImage?
        let banner: NebulaImage?
    }

    struct Link: Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, description, exclusivity, images
        case twitter, bluesky, instagram, facebook, reddit, patreon, website, merch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
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
