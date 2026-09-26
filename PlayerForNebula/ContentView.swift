import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Auth")

struct ContentView: View {
    enum Phase {
        case signingIn
        case loading
        case loaded([VideoEpisode])
        case failed(String)
    }

    @State private var phase = Phase.signingIn

    var body: some View {
        Group {
            switch phase {
            case .signingIn:
                SignInView { apiKey in
                    phase = .loading
                    Task { await loadEpisodes(apiKey: apiKey) }
                }
            case .loading:
                ProgressView()
            case .loaded(let episodes):
                List(episodes) { episode in
                    Text("\(episode.title) · \(episode.channelTitle) · \(episode.publishedAt)")
                }
            case .failed(let message):
                Text(message)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private func loadEpisodes(apiKey: String) async {
        do {
            let token = try await NebulaAPI.authorize(apiKey: apiKey)
            let (episodes, raw) = try await NebulaAPI.latestFollowedEpisodes(token: token)
            logger.info("video_episodes response structure:\n\(jsonStructure(raw), privacy: .public)")
            phase = .loaded(episodes)
        } catch {
            logger.error("Loading episodes failed: \(error, privacy: .public)")
            phase = .failed("Couldn't load videos: \(error.localizedDescription)")
        }
    }
}

private struct SignInView: View {
    let onSignedIn: (String) -> Void

    @State private var dataStore: WKWebsiteDataStore
    @State private var page: WebPage
    @State private var didSignIn = false

    init(onSignedIn: @escaping (String) -> Void) {
        self.onSignedIn = onSignedIn
        let dataStore = WKWebsiteDataStore.default()
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        _dataStore = State(initialValue: dataStore)
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    var body: some View {
        WebView(page)
            .onAppear {
                page.load(URL(string: "https://nebula.tv/login"))
            }
            // Nebula's web app navigates client-side after login, so this relies on
            // WebPage.url following history.pushState rather than on a page load.
            .onChange(of: page.url) { _, url in
                guard !didSignIn, url?.host() == "nebula.tv", url?.path() == "/featured" else { return }
                didSignIn = true
                Task { await readAPIKey() }
            }
    }

    private func readAPIKey() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
        guard let apiKey = cookies.first(where: { $0.name == NebulaAPI.apiKeyCookieName && $0.domain.hasSuffix("nebula.tv") })?.value else {
            logger.error("No \(NebulaAPI.apiKeyCookieName, privacy: .public) cookie after reaching /featured")
            didSignIn = false
            return
        }
        logger.info("Signed in, closing web view")
        onSignedIn(apiKey)
    }
}

#Preview {
    ContentView()
}
