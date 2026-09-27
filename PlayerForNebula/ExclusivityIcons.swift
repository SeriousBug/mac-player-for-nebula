import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "Icons")

/// Nebula's badge artwork is copyrighted, so it is read from nebula.tv at runtime instead of being bundled.
/// The web app inlines the badges as data URIs in its main script, next to the code that picks one per video.
@MainActor
@Observable
final class ExclusivityIcons {
    private(set) var images: [Exclusivity: NSImage] = [:]
    private var didLoad = false

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        do {
            images = try await Self.fetch()
        } catch {
            logger.error("Loading badge icons failed: \(error, privacy: .public)")
        }
    }

    private static func fetch() async throws -> [Exclusivity: NSImage] {
        let base = URL(string: "https://nebula.tv/")!
        let html = try await text(at: base)
        guard let scriptPath = html.firstMatch(of: /\/static\/index-[\w-]+\.js/)?.output else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let script = try await text(at: URL(string: String(scriptPath), relativeTo: base)!)

        guard let choice = script.firstMatch(
            of: /src:[\w$]+==="original"\?([\w$]+):[\w$]+==="plus"\?([\w$]+):([\w$]+)/
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let names: [Exclusivity: Substring] = [.original: choice.1, .plus: choice.2, .first: choice.3]

        var images: [Exclusivity: NSImage] = [:]
        for (exclusivity, name) in names {
            let pattern = try Regex<(Substring, Substring)>(
                "[,;{\\s]" + NSRegularExpression.escapedPattern(for: String(name)) + #"="data:image/png;base64,([A-Za-z0-9+/=]+)""#
            )
            guard let match = script.firstMatch(of: pattern),
                  let data = Data(base64Encoded: String(match.1)),
                  let image = NSImage(data: data)
            else { continue }
            images[exclusivity] = image
        }
        logger.info("Loaded badge icons: \(images.keys.map(\.rawValue).sorted(), privacy: .public)")
        return images
    }

    private static func text(at url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NebulaAPI.Error.badStatus(status, url) }
        return String(decoding: data, as: UTF8.self)
    }
}

struct ExclusivityIcon: View {
    let exclusivity: Exclusivity
    var size: CGFloat = 14

    @Environment(ExclusivityIcons.self) private var icons

    var body: some View {
        if let image = icons.images[exclusivity] {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("Nebula \(exclusivity.title)")
        }
    }
}
