import SwiftUI

@main
struct PlayerForNebulaApp: App {
    @State private var session = NebulaSession()
    @State private var exclusivityIcons = ExclusivityIcons()
    @State private var followStore = FollowStore()
    @State private var watchLaterStore = WatchLaterStore()
    @State private var savedEpisodesStore = SavedEpisodesStore()
    @State private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(followStore)
                .environment(watchLaterStore)
                .environment(savedEpisodesStore)
                .environment(exclusivityIcons)
                .task { await exclusivityIcons.load() }
                .task { await updateChecker.runAutomaticChecks() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updateChecker.isDownloading ? "Downloading Update…" : "Check for Updates…") {
                    Task { await updateChecker.check(userInitiated: true) }
                }
                .disabled(updateChecker.isChecking)
            }
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
