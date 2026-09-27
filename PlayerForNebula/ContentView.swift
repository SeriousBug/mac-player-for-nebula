import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "Auth")

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

enum LibraryTab: String, CaseIterable {
    case explore
    case latestVideos
    case followedChannels
    case watchLater
    case watchHistory
    case latestEpisodes
    case followedPodcasts
    case savedEpisodes
    case listenHistory
    case classes
    case store

    var title: LocalizedStringKey {
        switch self {
        case .explore: "Explore"
        case .latestVideos: "Latest Videos"
        case .followedChannels: "Followed Channels"
        case .watchLater: "Watch Later"
        case .watchHistory: "Watch History"
        case .latestEpisodes: "Latest Episodes"
        case .followedPodcasts: "Followed Podcasts"
        case .savedEpisodes: "Saved Episodes"
        case .listenHistory: "Listen History"
        case .classes: "Classes"
        case .store: "Store"
        }
    }

    var systemImage: String {
        switch self {
        case .explore: "safari"
        case .latestVideos: "play.rectangle"
        case .followedChannels: "person.2"
        case .watchLater: "clock"
        case .watchHistory: "clock.arrow.circlepath"
        case .latestEpisodes: "dot.radiowaves.left.and.right"
        case .followedPodcasts: "mic"
        case .savedEpisodes: "bookmark"
        case .listenHistory: "clock.arrow.circlepath"
        case .classes: "graduationcap"
        case .store: "bag"
        }
    }

    var externalURL: URL? {
        switch self {
        case .classes: URL(string: "https://nebula.tv/classes?utm_source=player-for-nebula")
        case .store: URL(string: "https://store.nebula.tv/?utm_source=player-for-nebula")
        default: nil
        }
    }
}

private struct LibraryView: View {
    @Environment(WatchLaterStore.self) private var watchLaterStore
    @Environment(SavedEpisodesStore.self) private var savedEpisodesStore
    @Environment(\.openURL) private var openURL
    @AppStorage("startupTab") private var startupTab = LibraryTab.latestVideos
    @State private var selectedTab: LibraryTab?

    var body: some View {
        TabView(selection: Binding { selectedTab ?? startupTab } set: { tab in
            if let url = tab.externalURL {
                openURL(url)
            } else {
                selectedTab = tab
            }
        }) {
            tab(.explore) {
                NavigationStack {
                    ExploreView()
                        .libraryDestinations()
                }
            }
            TabSection("Videos") {
                tab(.latestVideos) {
                    NavigationStack {
                        LatestVideosView()
                            .libraryDestinations()
                    }
                }
                tab(.followedChannels) {
                    NavigationStack {
                        FollowedChannelsView()
                            .libraryDestinations()
                    }
                }
                tab(.watchLater) {
                    NavigationStack {
                        EpisodeListView(
                            emptyMessage: "No videos saved to watch later",
                            version: watchLaterStore.version,
                            loadPage: NebulaAPI.watchLater
                        )
                            .libraryDestinations()
                    }
                }
                tab(.watchHistory) {
                    NavigationStack {
                        EpisodeListView(emptyMessage: "No watched videos yet", loadPage: NebulaAPI.watchHistory)
                            .libraryDestinations()
                    }
                }
            }
            TabSection("Podcasts") {
                tab(.latestEpisodes) {
                    NavigationStack {
                        PodcastEpisodeListView(
                            emptyMessage: "No episodes from podcasts you follow",
                            loadPage: NebulaAPI.latestFollowedPodcastEpisodes
                        )
                            .libraryDestinations()
                    }
                }
                tab(.followedPodcasts) {
                    NavigationStack {
                        FollowedPodcastsView()
                            .libraryDestinations()
                    }
                }
                tab(.savedEpisodes) {
                    NavigationStack {
                        PodcastEpisodeListView(
                            emptyMessage: "No saved episodes",
                            version: savedEpisodesStore.version,
                            loadPage: NebulaAPI.savedEpisodes
                        )
                            .libraryDestinations()
                    }
                }
                tab(.listenHistory) {
                    NavigationStack {
                        PodcastEpisodeListView(emptyMessage: "No episodes listened to yet", loadPage: NebulaAPI.listenHistory)
                            .libraryDestinations()
                    }
                }
            }
            tab(.classes) {}
            tab(.store) {}
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private func tab(_ tab: LibraryTab, @ViewBuilder content: () -> some View) -> some TabContent<LibraryTab> {
        Tab(tab.title, systemImage: tab.systemImage, value: tab, content: content)
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
        .navigationDestination(for: PodcastRoute.self) { route in
            PodcastView(slug: route.slug)
        }
        .navigationDestination(for: PodcastEpisode.self) { episode in
            PodcastPlayerView(episode: episode)
                .navigationTitle(episode.title)
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
