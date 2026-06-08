import Foundation

enum ClaudeHookInstaller {
    static let defaultSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    /// Events whose type is carried in the JSON payload (`hook_event_name`).
    /// `needsInput` comes from the dedicated `PermissionRequest`/`PermissionDenied`/`Elicitation`
    /// events. `Notification` is intentionally NOT here — its type is matcher-based (see below).
    private static let hookEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "UserPromptExpansion",
        "PreToolUse",
        "PermissionRequest",
        "PermissionDenied",
        "PostToolUse",
        "PostToolUseFailure",
        "PostToolBatch",
        "Elicitation",
        "ElicitationResult",
        "Stop",
        "StopFailure",
        "SubagentStart",
        "TaskCreated",
        "SessionEnd"
    ]

    private static let deprecatedHookEvents = [
        "SubagentStop",
        "TaskCompleted",
        "TeammateIdle"
    ]

    /// Notification types route via the hook `matcher` (the payload has no notification type).
    /// We pass the notification type to the binary as an arg so it never has to guess from the
    /// payload. Completion notifications use `idle_prompt`; permission/input alerts use the
    /// attention-related matchers.
    private static let notificationMatchers = [
        "idle_prompt",
        "permission_prompt",
        "elicitation_dialog"
    ]

    static func install(hookBinaryURL: URL, settingsURL: URL = defaultSettingsURL) throws {
        var settings = try readSettings(settingsURL)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let quotedPath = shellQuoted(hookBinaryURL.path)
        let entry = hookEntry(matcher: "", command: quotedPath)

        for event in deprecatedHookEvents {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let cleaned = entries.compactMap(removingAgentLightHooks)
            if cleaned.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = cleaned
            }
        }

        for event in hookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !entries.contains(where: containsAgentLightHook) {
                entries.append(entry)
            }
            hooks[event] = entries
        }

        var notificationEntries = hooks["Notification"] as? [[String: Any]] ?? []
        for matcher in notificationMatchers {
            let command = "\(quotedPath) \(matcher)"
            let alreadyPresent = notificationEntries.contains { entry in
                (entry["matcher"] as? String) == matcher && containsAgentLightHook(entry)
            }
            if !alreadyPresent {
                notificationEntries.append(hookEntry(matcher: matcher, command: command))
            }
        }
        hooks["Notification"] = notificationEntries

        settings["hooks"] = hooks
        try writeSettings(settings, to: settingsURL)
    }

    static func remove(settingsURL: URL = defaultSettingsURL) throws {
        var settings = try readSettings(settingsURL)
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in Array(hooks.keys) {
            guard let entries = hooks[key] as? [[String: Any]] else { continue }
            let cleaned = entries.compactMap(removingAgentLightHooks)
            if cleaned.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = cleaned
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettings(settings, to: settingsURL)
    }

    static func isInstalled(settingsURL: URL = defaultSettingsURL) -> Bool {
        guard let settings = try? readSettings(settingsURL),
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains(where: containsAgentLightHook)
        }
    }

    private static func hookEntry(matcher: String, command: String) -> [String: Any] {
        [
            "matcher": matcher,
            "hooks": [
                [
                    "type": "command",
                    "command": command
                ]
            ]
        ]
    }

    private static func removingAgentLightHooks(from entry: [String: Any]) -> [String: Any]? {
        guard let hookCommands = entry["hooks"] as? [[String: Any]] else {
            return containsAgentLightHook(entry) ? nil : entry
        }

        let remaining = hookCommands.filter { !isAgentLightHookCommand($0) }
        guard !remaining.isEmpty else { return nil }

        var copy = entry
        copy["hooks"] = remaining
        return copy
    }

    private static func containsAgentLightHook(_ entry: [String: Any]) -> Bool {
        guard let hookCommands = entry["hooks"] as? [[String: Any]] else {
            return isAgentLightHookCommand(entry)
        }
        return hookCommands.contains(where: isAgentLightHookCommand)
    }

    private static func isAgentLightHookCommand(_ commandEntry: [String: Any]) -> Bool {
        guard let command = commandEntry["command"] as? String else { return false }
        return command.contains("AgentClaudeHook")
    }

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
