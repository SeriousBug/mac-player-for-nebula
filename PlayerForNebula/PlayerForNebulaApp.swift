import SwiftUI

@main
struct PlayerForNebulaApp: App {
    @State private var session = NebulaSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
