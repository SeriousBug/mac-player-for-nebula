import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://nebula.tv"))
            .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
