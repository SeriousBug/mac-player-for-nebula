import SwiftUI

@main
struct PlayerForNebulaApp: App {
    @State private var session = NebulaSession()
    @State private var exclusivityIcons = ExclusivityIcons()
    @State private var followStore = FollowStore()
    @State private var watchLaterStore = WatchLaterStore()
    @State private var savedEpisodesStore = SavedEpisodesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(followStore)
                .environment(watchLaterStore)
                .environment(savedEpisodesStore)
                .environment(exclusivityIcons)
                .task { await exclusivityIcons.load() }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Sign Out") {
                    Task { await session.signOut() }
                }
                .disabled(!session.isSignedIn)
            }
        }
        Settings {
            SettingsView()
        }
    }
}
