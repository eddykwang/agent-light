import AgentTrafficLightsCore
import Foundation

enum CodexHookInstallStatus: Equatable {
    case notInstalled, configured, needsReinstall, invalidConfiguration
}

enum CodexHookInstaller {
    static var defaultHooksURL: URL { AgentConfigurationPaths.codexHome().appendingPathComponent("hooks.json") }
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                         "PostToolUse", "Stop", "Interrupt", "SessionEnd"]

    static func status(hookBinaryURL: URL, hooksURL: URL = defaultHooksURL) -> CodexHookInstallStatus {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return .notInstalled }
        guard let config = try? read(hooksURL) else { return .invalidConfiguration }
        let hooks = config["hooks"] as? [String: [[String: Any]]] ?? [:]
        let hasOurs = hooks.values.flatMap { $0 }.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
        }
        guard hasOurs else { return .notInstalled }
        return events.allSatisfy { event in
            (hooks[event] ?? []).contains { group in
                let matcher = group["matcher"] as? String ?? ""
                return ["", "*"].contains(matcher) &&
                    (group["hooks"] as? [[String: Any]] ?? []).contains { handler in
                        (handler["type"] as? String) == "command" &&
                        (handler["command"] as? String) == command(hookBinaryURL)
                    }
            }
        } ? .configured : .needsReinstall
    }

    static func install(hookBinaryURL: URL, hooksURL: URL = defaultHooksURL) throws {
        var config = try read(hooksURL)
        var hooks = removingOurs(config["hooks"] as? [String: [[String: Any]]] ?? [:])
        for event in events {
            hooks[event, default: []].append(["hooks": [["type": "command",
                "command": command(hookBinaryURL), "timeout": 1]]])
        }
        config["hooks"] = hooks
        try write(config, to: hooksURL)
    }

    static func remove(hooksURL: URL = defaultHooksURL,
                       eventsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-traffic-lights/codex-hooks")) throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            var config = try read(hooksURL)
            config["hooks"] = removingOurs(config["hooks"] as? [String: [[String: Any]]] ?? [:])
            try write(config, to: hooksURL)
        }
        for file in (try? FileManager.default.contentsOfDirectory(at: eventsRoot, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func command(_ binary: URL) -> String {
        "'\(binary.path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func isOurs(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.range(of: #"/AgentCodexHook(?:[\'\"]?(?:\s|$))"#, options: .regularExpression) != nil
    }

    private static func removingOurs(_ hooks: [String: [[String: Any]]]) -> [String: [[String: Any]]] {
        hooks.compactMapValues { groups in
            let cleaned = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = handlers.filter { !isOurs($0) }
                guard !remaining.isEmpty else { return nil }
                var copy = group; copy["hooks"] = remaining; return copy
            }
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let config = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              config["hooks"] == nil || config["hooks"] is [String: [[String: Any]]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return config
    }

    private static func write(_ config: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
