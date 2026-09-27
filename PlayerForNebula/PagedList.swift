import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "PagedList")

/// Items from a paginated endpoint, loaded one page at a time as the user scrolls.
@MainActor
@Observable
final class PagedList<Item: Identifiable & Decodable & Sendable> {
    typealias LoadPage = (_ pageURL: URL?, _ token: String) async throws -> Page<Item>

    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var error: (any Error)?

    private var query: AnyHashable?
    private var loadPage: LoadPage?
    private var nextPage: URL?
    private var hasMore = true
    /// Bumped whenever the query changes, so a page that was requested for the old query is dropped.
    private var generation = 0
    /// The previous query's items stay visible until the first page for the new one arrives,
    /// so the grid doesn't collapse and reset the scroll position.
    private var replacesItems = false

    /// Starts over when `query` differs from the loaded one. Views call this whenever they appear,
    /// so coming back from a pushed page keeps the loaded items and scroll position.
    func load(_ query: some Hashable, session: NebulaSession, loadPage: @escaping LoadPage) async {
        let query = AnyHashable(query)
        guard query != self.query else { return }
        self.query = query
        self.loadPage = loadPage
        generation += 1
        replacesItems = true
        nextPage = nil
        hasMore = true
        isLoading = false
        error = nil
        await loadMore(session: session)
    }

    func reload(session: NebulaSession) async {
        guard let query, let loadPage else { return }
        self.query = nil
        await load(query, session: session, loadPage: loadPage)
    }

    func loadMore(session: NebulaSession) async {
        guard let loadPage, hasMore, !isLoading else { return }
        isLoading = true
        error = nil
        let generation = generation
        let pageURL = nextPage
        defer {
            if generation == self.generation { isLoading = false }
        }
        do {
            let page = try await session.withToken { try await loadPage(pageURL, $0) }
            guard generation == self.generation else { return }
            if replacesItems {
                items = page.results
                replacesItems = false
            } else {
                items += page.results
            }
            nextPage = page.next
            hasMore = page.next != nil
        } catch NebulaSession.Error.signedOut {
            return
        } catch {
            guard generation == self.generation else { return }
            if replacesItems {
                items = []
                replacesItems = false
            }
            logger.error("Loading page failed: \(error, privacy: .public)")
            self.error = error
        }
    }
}

struct PagedListFooter<Item: Identifiable & Decodable & Sendable>: View {
    let list: PagedList<Item>
    let errorTitle: String
    let emptyMessage: String

    @Environment(NebulaSession.self) private var session

    var body: some View {
        Group {
            if list.isLoading {
                ProgressView()
            } else if let error = list.error {
                VStack {
                    Text("\(errorTitle): \(error.localizedDescription)")
                    Button("Try Again") { Task { await list.loadMore(session: session) } }
                }
            } else if list.items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

protocol SortOrder: CaseIterable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
}

extension DateOrdering: SortOrder {}
extension ExploreChannelsOrdering: SortOrder {}
extension PodcastsOrdering: SortOrder {}
extension FollowedChannelsOrdering: SortOrder {}

struct SortPicker<Order: SortOrder>: View {
    @Binding var selection: Order

    var body: some View {
        Picker("Sort By", selection: $selection) {
            ForEach(Order.allCases, id: \.self) { order in
                Text(order.title).tag(order)
            }
        }
        .pickerStyle(.menu)
    }
}
