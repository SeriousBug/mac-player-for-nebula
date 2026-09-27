import SwiftUI

struct SettingsView: View {
    @AppStorage("startupTab") private var startupTab = LibraryTab.latestVideos
    @AppStorage(UpdateChecker.automaticChecksKey) private var checkForUpdates = true

    var body: some View {
        Form {
            Picker("Open at launch:", selection: $startupTab) {
                ForEach(LibraryTab.allCases.filter { $0.externalURL == nil }, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            Toggle("Check for updates automatically", isOn: $checkForUpdates)
        }
        .padding(20)
        .frame(width: 350)
    }
}
