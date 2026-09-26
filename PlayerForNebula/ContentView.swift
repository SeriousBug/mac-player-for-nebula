import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.example.PlayerForNebula", category: "Auth")

struct ContentView: View {
    @State private var page = WebPage()
    @State private var isSignedIn = false

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
            }
    }
}

#Preview {
    ContentView()
}
