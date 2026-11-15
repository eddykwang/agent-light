import Foundation

public enum AgentConfigurationPaths {
    public static func codexHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        directory(environment["CODEX_HOME"], fallback: ".codex")
    }

    public static func claudeHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        directory(environment["CLAUDE_CONFIG_DIR"], fallback: ".claude")
    }

    private static func directory(_ value: String?, fallback: String) -> URL {
        if let path = value?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallback, isDirectory: true)
    }
}
