import SwiftUI

struct SettingsView: View {
    @AppStorage("startupTab") private var startupTab = LibraryTab.latestVideos

    var body: some View {
        Form {
            Picker("Open at launch:", selection: $startupTab) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}
