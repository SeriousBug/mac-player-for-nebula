import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "EpisodeList")

/// An infinitely scrolling grid of videos from a paginated endpoint.
struct EpisodeListView: View {
    typealias LoadPage = (_ pageURL: URL?, _ token: String) async throws -> EpisodePage

    let emptyMessage: String
    /// Changing this marks the loaded videos as stale, so they are reloaded the next time the list appears.
    var version = 0
    let loadPage: LoadPage

    @Environment(NebulaSession.self) private var session
    @State private var model = EpisodeListModel()

    var body: some View {
        VideoGrid(
            episodes: model.episodes,
            onReachEnd: { Task { await model.loadMore(loadPage, session: session) } },
            header: { EmptyView() },
            footer: { footer }
        )
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.reload(loadPage, version: version, session: session) }
            }
            .keyboardShortcut("r")
        }
        .onAppear {
            guard model.loadedVersion != version else { return }
            Task { await model.reload(loadPage, version: version, session: session) }
        }
    }

    @ViewBuilder private var footer: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = model.errorMessage {
            VStack {
                Text(errorMessage)
                Button("Try Again") { Task { await model.loadMore(loadPage, session: session) } }
            }
            .frame(maxWidth: .infinity)
        } else if model.episodes.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

@MainActor
@Observable
private final class EpisodeListModel {
    private(set) var episodes: [VideoEpisode] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedVersion: Int?

    private var nextPage: URL?
    private var hasMore = true
    /// Bumped on every reload, so a page that was requested before it is dropped.
    private var generation = 0

    func reload(_ loadPage: EpisodeListView.LoadPage, version: Int, session: NebulaSession) async {
        loadedVersion = version
        generation += 1
        episodes = []
        nextPage = nil
        hasMore = true
        isLoading = false
        errorMessage = nil
        await loadMore(loadPage, session: session)
    }

    func loadMore(_ loadPage: EpisodeListView.LoadPage, session: NebulaSession) async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let generation = generation
        let pageURL = nextPage
        defer {
            if generation == self.generation { isLoading = false }
        }
        do {
            let page = try await session.withToken { try await loadPage(pageURL, $0) }
            guard generation == self.generation else { return }
            episodes += page.results
            nextPage = page.next
            hasMore = page.next != nil
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            guard generation == self.generation else { return }
            logger.error("Loading episodes failed: \(error, privacy: .public)")
            errorMessage = "Couldn't load videos: \(error.localizedDescription)"
        }
    }
}
