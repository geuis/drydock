import AppKit
import Foundation

// A release version like "1.2.3", compared number by number so 0.10.0 is newer
// than 0.9.0. Git tags carry a leading "v" and local builds carry a "-dev"
// suffix; both are ignored.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        var text: String = string.trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }

        let core: Substring = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        var numbers: [Int] = []

        for part in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(part), number >= 0 else { return nil }

            numbers.append(number)
        }

        guard !numbers.isEmpty else { return nil }

        components = numbers
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    // Missing trailing parts count as zero, so "1.0" equals "1.0.0".
    private static func paddedPairs(_ lhs: AppVersion, _ rhs: AppVersion) -> [(Int, Int)] {
        let count: Int = max(lhs.components.count, rhs.components.count)

        return (0..<count).map { index in
            let left: Int = index < lhs.components.count ? lhs.components[index] : 0
            let right: Int = index < rhs.components.count ? rhs.components[index] : 0

            return (left, right)
        }
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        paddedPairs(lhs, rhs).allSatisfy { $0.0 == $0.1 }
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (left, right) in paddedPairs(lhs, rhs) where left != right {
            return left < right
        }

        return false
    }
}

// The fields Drydock needs from GitHub's "latest release" API response.
public struct LatestRelease: Decodable, Equatable {
    public let tagName: String
    public let pageURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
    }
}

public enum UpdateCheckResult: Equatable {
    case updateAvailable(version: AppVersion, pageURL: URL)
    case upToDate
}

public enum UpdateCheckError: LocalizedError {
    case unexpectedResponse(statusCode: Int)
    case unreadableVersion(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse(let statusCode):
            return "GitHub answered with status \(statusCode)."
        case .unreadableVersion(let tag):
            return "The latest release has a version Drydock can't read (\(tag))."
        }
    }
}

// Checks GitHub for a newer release and points the user at its download page.
// Deliberately doesn't download or install anything: updates are expected to
// be rare, so a notice is enough.
@MainActor
public final class UpdateChecker {
    public static let shared: UpdateChecker = UpdateChecker()

    // "latest" never returns drafts or pre-releases.
    private static let latestReleaseURL: URL = URL(string: "https://api.github.com/repos/geuis/drydock/releases/latest")!
    private static let skippedVersionKey: String = "skippedUpdateVersion"

    private var isChecking: Bool = false

    private init() {}

    // Nil when running outside a packaged app (for example `swift run`), which
    // has no version to compare.
    public static var currentVersion: AppVersion? {
        guard let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        return AppVersion(versionString)
    }

    public static func evaluate(_ release: LatestRelease, currentVersion: AppVersion) throws -> UpdateCheckResult {
        guard let latestVersion = AppVersion(release.tagName) else {
            throw UpdateCheckError.unreadableVersion(release.tagName)
        }

        guard currentVersion < latestVersion else { return .upToDate }

        return .updateAvailable(version: latestVersion, pageURL: release.pageURL)
    }

    // The launch check stays silent unless there is something new, and
    // respects "Skip This Version".
    public func checkAutomatically() {
        Task { await check(userInitiated: false) }
    }

    public func checkFromMenu() {
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !isChecking else { return }

        guard let currentVersion = Self.currentVersion else {
            if userInitiated {
                showMessage(title: "Can't check for updates", detail: "Update checks only work in a packaged build of Drydock.")
            }

            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let release: LatestRelease = try await Self.fetchLatestRelease()

            switch try Self.evaluate(release, currentVersion: currentVersion) {
            case .upToDate:
                if userInitiated {
                    showMessage(title: "You're up to date", detail: "Drydock \(currentVersion) is the newest version.")
                }

            case .updateAvailable(let latestVersion, let pageURL):
                let skippedVersion: String? = UserDefaults.standard.string(forKey: Self.skippedVersionKey)

                if !userInitiated && skippedVersion == latestVersion.description {
                    return
                }

                presentUpdate(latestVersion: latestVersion, currentVersion: currentVersion, pageURL: pageURL)
            }
        } catch {
            // A failed launch check isn't worth interrupting the user for.
            if userInitiated {
                showMessage(title: "Couldn't check for updates", detail: error.localizedDescription)
            }
        }
    }

    private static func fetchLatestRelease() async throws -> LatestRelease {
        var request: URLRequest = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode: Int = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            throw UpdateCheckError.unexpectedResponse(statusCode: statusCode)
        }

        return try JSONDecoder().decode(LatestRelease.self, from: data)
    }

    private func presentUpdate(latestVersion: AppVersion, currentVersion: AppVersion, pageURL: URL) {
        let alert: NSAlert = NSAlert()
        alert.messageText = "Drydock \(latestVersion) is available"
        alert.informativeText = "You have version \(currentVersion). The download page has the new version and what changed."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(pageURL)

        case .alertThirdButtonReturn:
            UserDefaults.standard.set(latestVersion.description, forKey: Self.skippedVersionKey)

        default:
            break
        }
    }

    private func showMessage(title: String, detail: String) {
        let alert: NSAlert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
