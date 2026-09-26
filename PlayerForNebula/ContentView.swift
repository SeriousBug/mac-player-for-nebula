import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Auth")

struct ContentView: View {
    @State private var dataStore: WKWebsiteDataStore
    @State private var page: WebPage
    @State private var isSignedIn = false

    init() {
        let dataStore = WKWebsiteDataStore.default()
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        _dataStore = State(initialValue: dataStore)
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    var body: some View {
        WebView(page)
            .frame(minWidth: 800, minHeight: 500)
            .onAppear {
                page.load(URL(string: "https://nebula.tv/login"))
            }
            // Nebula's web app navigates client-side after login, so this relies on
            // WebPage.url following history.pushState rather than on a page load.
            .onChange(of: page.url) { _, url in
                guard !isSignedIn, url?.host() == "nebula.tv", url?.path() == "/featured" else { return }
                isSignedIn = true
                logger.info("Reached /featured, user is signed in")
                Task { await authenticate() }
            }
    }

    private func authenticate() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
        guard let apiKey = cookies.first(where: { $0.name == NebulaAPI.apiKeyCookieName && $0.domain.hasSuffix("nebula.tv") })?.value else {
            logger.error("No \(NebulaAPI.apiKeyCookieName, privacy: .public) cookie after sign-in")
            return
        }
        do {
            let token = try await NebulaAPI.authorize(apiKey: apiKey)
            let episodes = try await NebulaAPI.followingEpisodes(token: token)
            logger.info("Authorized, fetched \(episodes.count) followed episodes; first: \(episodes.first?.title ?? "-", privacy: .public)")
        } catch {
            logger.error("Authorization failed: \(error, privacy: .public)")
        }
    }
}

#Preview {
    ContentView()
}
