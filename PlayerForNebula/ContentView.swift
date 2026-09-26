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
    @Environment(WatchLaterStore.self) private var watchLaterStore

    var body: some View {
        TabView {
            Tab("Latest Videos", systemImage: "play.rectangle") {
                NavigationStack {
                    LatestVideosView()
                        .libraryDestinations()
                }
            }
            Tab("Followed Channels", systemImage: "person.2") {
                NavigationStack {
                    FollowedChannelsView()
                        .libraryDestinations()
                }
            }
            Tab("Watch Later", systemImage: "clock") {
                NavigationStack {
                    EpisodeListView(
                        emptyMessage: "No videos saved to watch later",
                        version: watchLaterStore.version,
                        loadPage: NebulaAPI.watchLater
                    )
                        .libraryDestinations()
                }
            }
            Tab("Watch History", systemImage: "clock.arrow.circlepath") {
                NavigationStack {
                    EpisodeListView(emptyMessage: "No watched videos yet", loadPage: NebulaAPI.watchHistory)
                        .libraryDestinations()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

private extension View {
    func libraryDestinations() -> some View {
        navigationDestination(for: VideoEpisode.self) { episode in
            PlayerView(episode: episode)
                .navigationTitle(episode.title)
        }
        .navigationDestination(for: ChannelRoute.self) { route in
            ChannelView(slug: route.slug)
        }
    }
}

private struct LatestVideosView: View {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await loadEpisodes() }
        case .loaded(let episodes):
            VideoGrid(episodes: episodes)
        case .failed(let message):
            VStack {
                Text(message)
                Button("Try Again") { phase = .loading }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Signs in with the saved Nebula cookie when there is one. Otherwise loads the login page out of sight
/// and only reveals it if Nebula doesn't redirect away from it, which means the user has to log in.
private struct SignInView: View {
    let onSignedIn: (String) -> Void

    @State private var dataStore: WKWebsiteDataStore
    @State private var page: WebPage
    @State private var isLoginPageVisible = false
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
        ZStack {
            WebView(page)
                .opacity(isLoginPageVisible ? 1 : 0)
            if !isLoginPageVisible {
                ProgressView()
            }
        }
        .task {
            if let apiKey = await savedAPIKey() {
                logger.info("Signing in with saved cookie")
                didSignIn = true
                onSignedIn(apiKey)
                return
            }
            page.load(URL(string: "https://nebula.tv/login"))
        }
        // Nebula's web app navigates client-side after login, so this relies on
        // WebPage.url following history.pushState rather than on a page load.
        .onChange(of: page.url) { _, url in
            guard !didSignIn, url?.host() == "nebula.tv", url?.path() == "/featured" else { return }
            didSignIn = true
            Task { await finishSignIn() }
        }
        .onChange(of: page.isLoading) { _, isLoading in
            guard !isLoading, !isLoginPageVisible else { return }
            Task {
                // A signed-in session redirects from /login client-side shortly after the page loads.
                try? await Task.sleep(for: .seconds(1.5))
                if !didSignIn, page.url?.path().hasPrefix("/login") == true {
                    isLoginPageVisible = true
                }
            }
        }
    }

    private func savedAPIKey() async -> String? {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return cookies.first { $0.name == NebulaAPI.apiKeyCookieName && $0.domain.hasSuffix("nebula.tv") }?.value
    }

    private func finishSignIn() async {
        guard let apiKey = await savedAPIKey() else {
            logger.error("No \(NebulaAPI.apiKeyCookieName, privacy: .public) cookie after reaching /featured")
            didSignIn = false
            isLoginPageVisible = true
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
