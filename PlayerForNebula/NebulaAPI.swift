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
        return try await send(request, as: Response.self).token
    }

    static func followingEpisodes(token: String) async throws -> [VideoEpisode] {
        struct Response: Decodable { let results: [VideoEpisode] }
        var components = URLComponents(string: "https://content.api.nebula.app/video_episodes/")!
        components.queryItems = [
            URLQueryItem(name: "following", value: "true"),
            URLQueryItem(name: "ordering", value: "-published_at"),
            URLQueryItem(name: "page_size", value: "24"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request, as: Response.self).results
    }

    private static func send<T: Decodable>(_ request: URLRequest, as _: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Error.badStatus(status, request.url!) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct VideoEpisode: Decodable, Identifiable {
    let id: String
    let title: String
}
