import AppKit
import OSLog

private let logger = Logger(subsystem: "dev.bgenc.player-for-nebula", category: "Updates")

@MainActor
@Observable
final class UpdateChecker {
    static let automaticChecksKey = "checkForUpdatesAutomatically"

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        var downloadURL: URL {
            assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadUrl ?? htmlUrl
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/SeriousBug/mac-player-for-nebula/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedVersionKey = "skippedUpdateVersion"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var isChecking = false
    private var isRunningAutomaticChecks = false

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Keeps running while a window is open so that a Mac left running for days still checks once a day.
    /// Every window starts this, so only the first one runs the loop.
    func runAutomaticChecks() async {
        guard !isRunningAutomaticChecks else { return }
        isRunningAutomaticChecks = true
        defer { isRunningAutomaticChecks = false }
        UserDefaults.standard.register(defaults: [Self.automaticChecksKey: true])
        while !Task.isCancelled {
            if UserDefaults.standard.bool(forKey: Self.automaticChecksKey) {
                let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
                if Date.now.timeIntervalSince(lastCheck) >= Self.checkInterval {
                    await check(userInitiated: false)
                }
            }
            try? await Task.sleep(for: .seconds(60 * 60))
        }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let release: Release
        do {
            release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
        } catch {
            logger.error("Update check failed: \(error, privacy: .public)")
            if userInitiated {
                showAlert(
                    message: "Couldn’t check for updates",
                    info: error.localizedDescription
                )
            }
            return
        }

        guard Self.isVersion(release.version, newerThan: currentVersion) else {
            if userInitiated {
                showAlert(
                    message: "You’re up to date",
                    info: "Player for Nebula \(currentVersion) is the latest version."
                )
            }
            return
        }

        let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
        if !userInitiated && skipped == release.version { return }

        promptToUpdate(to: release)
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NebulaAPI.Error.badStatus(status, Self.latestReleaseURL) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Release.self, from: data)
    }

    private func promptToUpdate(to release: Release) {
        let alert = NSAlert()
        alert.messageText = "Player for Nebula \(release.version) is available"
        alert.informativeText = "You have version \(currentVersion). Download the new version and drag it into your Applications folder to replace this one."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
        default:
            break
        }
    }

    private func showAlert(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}
