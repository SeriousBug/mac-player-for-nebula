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
        return (try JSONDecoder().decode(Response.self, from: data).results, data)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Error.badStatus(status, request.url!) }
        return data
    }
}

struct VideoEpisode: Decodable, Identifiable {
    let id: String
    let title: String
    let channelTitle: String
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case channelTitle = "channel_title"
        case publishedAt = "published_at"
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
