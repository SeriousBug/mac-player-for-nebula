import Foundation
import OSLog
import WebKit

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Auth")

/// Holds the API key from sign-in and hands out a JWT, refreshing it before it expires.
@MainActor
@Observable
final class NebulaSession {
    enum Error: Swift.Error {
        case signedOut
    }

    private struct Token {
        let value: String
        let expiresAt: Date
    }

    private(set) var isSignedIn = false
    private var apiKey: String?
    private var token: Token?
    private var refreshTask: Task<Token, Swift.Error>?

    func signIn(apiKey: String) {
        self.apiKey = apiKey
        token = nil
        isSignedIn = true
    }

    /// Clears Nebula's website data too, otherwise the web view would sign straight back in with the stale cookie.
    func signOut() async {
        logger.info("Signing out")
        apiKey = nil
        token = nil
        refreshTask?.cancel()
        refreshTask = nil
        isSignedIn = false

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("nebula") })
    }

    /// Runs `operation` with a valid JWT. On an auth rejection it retries once with a fresh token,
    /// and signs out if that fails too.
    func withToken<T>(_ operation: (String) async throws -> T) async throws -> T {
        do {
            return try await operation(validToken())
        } catch let error where Self.isAuthFailure(error) {
            logger.info("Request rejected, refreshing token and retrying")
            token = nil
        }
        do {
            return try await operation(validToken())
        } catch let error where Self.isAuthFailure(error) {
            await signOut()
            throw Error.signedOut
        }
    }

    private func validToken() async throws -> String {
        if let token, token.expiresAt > .now.addingTimeInterval(60) {
            return token.value
        }
        if let refreshTask {
            return try await refreshTask.value.value
        }
        guard let apiKey else { throw Error.signedOut }

        let task = Task {
            let value = try await NebulaAPI.authorize(apiKey: apiKey)
            let claims = try JWTClaims(decoding: value)
            // An unrecognized key still gets a token, but an anonymous one.
            guard !claims.isAnonymous else { throw Error.signedOut }
            return Token(value: value, expiresAt: claims.expiresAt)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let newToken = try await task.value
            token = newToken
            logger.info("Refreshed token, expires \(newToken.expiresAt, privacy: .public)")
            return newToken.value
        } catch let error where Self.isAuthFailure(error) {
            await signOut()
            throw Error.signedOut
        }
    }

    private static func isAuthFailure(_ error: Swift.Error) -> Bool {
        switch error {
        case Error.signedOut:
            true
        case NebulaAPI.Error.badStatus(let status, _):
            status == 401 || status == 403
        default:
            false
        }
    }
}

private struct JWTClaims: Decodable {
    let expiresAt: Date
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case expiresAt = "exp"
        case isAnonymous = "is_anonymous"
    }

    init(decoding jwt: String) throws {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a JWT")) }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid JWT payload"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self = try decoder.decode(Self.self, from: data)
    }
}
