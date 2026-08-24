import Foundation

enum CopilotHookInstallStatus: Equatable {
    case notInstalled
    case installed
    case needsReinstall
    case conflict
}

enum CopilotHookInstallerError: LocalizedError {
    case conflictingConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .conflictingConfiguration(let path):
            return "A non-Agent Light hook file already exists at \(path). Move or rename it before installing."
        }
    }
}

enum CopilotHookInstaller {
    private static let hookEvents = [
        "sessionStart",
        "userPromptSubmitted",
        "postToolUse",
        "postToolUseFailure",
        "agentStop",
        "errorOccurred",
        "sessionEnd"
    ]
    private static let notificationMatcher = "permission_prompt|elicitation_dialog"
    private static let timeoutSeconds = 2

    static var defaultHooksURL: URL {
        copilotHomeURL.appendingPathComponent("hooks/agent-light.json")
    }

    static var defaultEventsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-traffic-lights/copilot-hooks", isDirectory: true)
    }

    static func status(
        hookBinaryURL: URL,
        hooksURL: URL = defaultHooksURL
    ) -> CopilotHookInstallStatus {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return .notInstalled
        }
        guard let configuration = try? readConfiguration(hooksURL) else {
            return .conflict
        }
        guard containsAgentLightHook(configuration) else {
            return .conflict
        }
        return isCurrent(configuration, hookBinaryURL: hookBinaryURL) ? .installed : .needsReinstall
    }

    static func install(
        hookBinaryURL: URL,
        hooksURL: URL = defaultHooksURL
    ) throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            guard let existing = try? readConfiguration(hooksURL),
                  containsAgentLightHook(existing) else {
                throw CopilotHookInstallerError.conflictingConfiguration(hooksURL.path)
            }
        }

        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeConfiguration(configuration(hookBinaryURL: hookBinaryURL), to: hooksURL)
    }

    static func remove(
        hooksURL: URL = defaultHooksURL,
        eventsRoot: URL = defaultEventsRoot
    ) throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            guard let existing = try? readConfiguration(hooksURL),
                  containsAgentLightHook(existing) else {
                throw CopilotHookInstallerError.conflictingConfiguration(hooksURL.path)
            }
            try FileManager.default.removeItem(at: hooksURL)
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: eventsRoot,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static var copilotHomeURL: URL {
        if let customHome = ProcessInfo.processInfo.environment["COPILOT_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customHome.isEmpty {
            return URL(fileURLWithPath: customHome, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot", isDirectory: true)
    }

    private static func configuration(hookBinaryURL: URL) -> [String: Any] {
        var hooks: [String: Any] = [:]
        for event in hookEvents {
            hooks[event] = [commandEntry(event: event, hookBinaryURL: hookBinaryURL)]
        }
        hooks["notification"] = [[
            "type": "command",
            "matcher": notificationMatcher,
            "bash": command(event: "notification", hookBinaryURL: hookBinaryURL),
            "timeoutSec": timeoutSeconds
        ]]
        return ["version": 1, "hooks": hooks]
    }

    private static func commandEntry(event: String, hookBinaryURL: URL) -> [String: Any] {
        [
            "type": "command",
            "bash": command(event: event, hookBinaryURL: hookBinaryURL),
            "timeoutSec": timeoutSeconds
        ]
    }

    private static func command(event: String, hookBinaryURL: URL) -> String {
        "\(shellQuoted(hookBinaryURL.path)) \(event)"
    }

    private static func isCurrent(_ configuration: [String: Any], hookBinaryURL: URL) -> Bool {
        guard (configuration["version"] as? NSNumber)?.intValue == 1,
              let hooks = configuration["hooks"] as? [String: Any] else {
            return false
        }

        for event in hookEvents {
            guard let entries = hooks[event] as? [[String: Any]],
                  entries.contains(where: { entry in
                      (entry["type"] as? String) == "command"
                          && (entry["bash"] as? String) == command(event: event, hookBinaryURL: hookBinaryURL)
                  }) else {
                return false
            }
        }

        guard let notifications = hooks["notification"] as? [[String: Any]] else {
            return false
        }
        return notifications.contains { entry in
            (entry["type"] as? String) == "command"
                && (entry["matcher"] as? String) == notificationMatcher
                && (entry["bash"] as? String) == command(event: "notification", hookBinaryURL: hookBinaryURL)
        }
    }

    private static func containsAgentLightHook(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.contains("AgentCopilotHook")
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsAgentLightHook)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsAgentLightHook)
        }
        return false
    }

    private static func readConfiguration(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty,
              let configuration = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CopilotHookInstallerError.conflictingConfiguration(url.path)
        }
        return configuration
    }

    private static func writeConfiguration(_ configuration: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
