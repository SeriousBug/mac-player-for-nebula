import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://nebula.tv/login"))
            .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
