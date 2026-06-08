import Foundation

struct AppUpdate: Equatable {
    let version: String
    let pageURL: URL
    let currentVersion: String
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AppUpdate)
    case failed(String)
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/eddykwang/agent-light/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    private enum Keys {
        static let lastUpdateCheckAt = "lastUpdateCheckAt"
        static let lastNotifiedUpdateVersion = "lastNotifiedUpdateVersion"
    }

    private let defaults: UserDefaults
    private let currentVersionProvider: () -> String
    private let fetchLatestRelease: (URL) async throws -> Data

    @Published private(set) var state: UpdateCheckState = .idle

    var availableUpdate: AppUpdate? {
        if case let .updateAvailable(update) = state {
            return update
        }
        return nil
    }

    init(
        defaults: UserDefaults = .standard,
        currentVersionProvider: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        },
        fetchLatestRelease: @escaping (URL) async throws -> Data = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider
        self.fetchLatestRelease = fetchLatestRelease
    }

    func checkIfNeeded(force: Bool = false) async {
        if !force, !shouldCheckNow() {
            return
        }

        await checkNow()
    }

    func checkNow() async {
        state = .checking
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUpdateCheckAt)

        do {
            let data = try await fetchLatestRelease(Self.latestReleaseURL)
            if let update = try Self.parseLatestRelease(data, currentVersion: currentVersionProvider()) {
                state = .updateAvailable(update)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func shouldNotifyUser(about update: AppUpdate) -> Bool {
        defaults.string(forKey: Keys.lastNotifiedUpdateVersion) != update.version
    }

    func markUserNotified(about update: AppUpdate) {
        defaults.set(update.version, forKey: Keys.lastNotifiedUpdateVersion)
    }

    private func shouldCheckNow(now: Date = Date()) -> Bool {
        let lastCheck = defaults.double(forKey: Keys.lastUpdateCheckAt)
        guard lastCheck > 0 else {
            return true
        }
        return now.timeIntervalSince1970 - lastCheck >= Self.checkInterval
    }

    nonisolated static func parseLatestRelease(_ data: Data, currentVersion: String) throws -> AppUpdate? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        guard compareVersions(latestVersion, currentVersion) == .orderedDescending,
              let pageURL = URL(string: release.htmlURL) else {
            return nil
        }

        return AppUpdate(version: latestVersion, pageURL: pageURL, currentVersion: currentVersion)
    }

    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericVersionParts(lhs)
        let rhsParts = numericVersionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private nonisolated static func numericVersionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
