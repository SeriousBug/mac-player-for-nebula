import SwiftUI

@main
struct PlayerForNebulaApp: App {
    @State private var session = NebulaSession()
    @State private var exclusivityIcons = ExclusivityIcons()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(exclusivityIcons)
                .task { await exclusivityIcons.load() }
        }
    }
}
