import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Auth")

struct ContentView: View {
    @Environment(NebulaSession.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                LibraryView()
            } else {
                SignInView { apiKey in
                    session.signIn(apiKey: apiKey)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

private struct LibraryView: View {
    enum Phase {
        case loading
        case loaded([VideoEpisode])
        case failed(String)
    }

    @Environment(NebulaSession.self) private var session
    @State private var phase = Phase.loading

    var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .task { await loadEpisodes() }
        case .loaded(let episodes):
            NavigationStack {
                VideoGrid(episodes: episodes)
                    .navigationDestination(for: VideoEpisode.self) { episode in
                        PlayerView(episode: episode)
                            .navigationTitle(episode.title)
                    }
            }
        case .failed(let message):
            VStack {
                Text(message)
                Button("Try Again") { phase = .loading }
            }
        }
    }

    private func loadEpisodes() async {
        do {
            let (episodes, raw) = try await session.withToken(NebulaAPI.latestFollowedEpisodes)
            logger.info("video_episodes response structure:\n\(jsonStructure(raw), privacy: .public)")
            phase = .loaded(episodes)
        } catch NebulaSession.Error.signedOut {
            return
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
        .environment(NebulaSession())
}
