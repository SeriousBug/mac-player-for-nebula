import SwiftUI

@main
struct PlayerForNebulaApp: App {
    @State private var session = NebulaSession()
    @State private var exclusivityIcons = ExclusivityIcons()
    @State private var followStore = FollowStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(followStore)
                .environment(exclusivityIcons)
                .task { await exclusivityIcons.load() }
        }
    }
}
