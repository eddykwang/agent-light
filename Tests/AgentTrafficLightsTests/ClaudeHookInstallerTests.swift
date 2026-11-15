import XCTest
@testable import AgentTrafficLights

final class ClaudeHookInstallerTests: XCTestCase {
    func testInstallAddsAgentLightHooksAndPreservesExistingHooks() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        let existing = """
        {
          "hooks": {
            "Stop": [
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "echo existing" }
                ]
              }
            ]
          }
        }
        """
        try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

        try ClaudeHookInstaller.install(
            hookBinaryURL: URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook"),
            settingsURL: settingsURL
        )

        let object = try readJSONObject(settingsURL)
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let stopEntries = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopEntries.count, 2)
        XCTAssertTrue(ClaudeHookInstaller.isInstalled(hookBinaryURL: URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook"), settingsURL: settingsURL))
        XCTAssertNotNil(hooks["SessionStart"])
        XCTAssertNotNil(hooks["PermissionRequest"])
        XCTAssertNotNil(hooks["PermissionDenied"])
        XCTAssertNotNil(hooks["PostToolBatch"])
        XCTAssertNotNil(hooks["Notification"])
    }

    func testRemoveDeletesOnlyAgentLightHooks() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        try ClaudeHookInstaller.install(
            hookBinaryURL: URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook"),
            settingsURL: settingsURL
        )

        try ClaudeHookInstaller.remove(settingsURL: settingsURL)

        let object = try readJSONObject(settingsURL)
        XCTAssertFalse(ClaudeHookInstaller.isInstalled(hookBinaryURL: URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook"), settingsURL: settingsURL))
        XCTAssertNil(object["hooks"])
    }

    func testNotificationHooksAreMatcherSpecificWithTypeArgument() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        try ClaudeHookInstaller.install(
            hookBinaryURL: URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook"),
            settingsURL: settingsURL
        )

        let object = try readJSONObject(settingsURL)
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let notification = try XCTUnwrap(hooks["Notification"] as? [[String: Any]])

        let matchers = notification.compactMap { $0["matcher"] as? String }.sorted()
        XCTAssertEqual(matchers, ["elicitation_dialog", "idle_prompt", "permission_prompt"])

        // Each entry passes its notification type to the binary as a command argument.
        for entry in notification {
            let matcher = try XCTUnwrap(entry["matcher"] as? String)
            let commands = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
            let command = try XCTUnwrap(commands.first?["command"] as? String)
            XCTAssertTrue(command.contains("AgentClaudeHook"))
            XCTAssertTrue(command.hasSuffix(" \(matcher)"), "command should pass the matcher type as an argument: \(command)")
        }
    }

    func testInstallIsIdempotentForNotificationMatchers() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        let binary = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook")
        try ClaudeHookInstaller.install(hookBinaryURL: binary, settingsURL: settingsURL)
        try ClaudeHookInstaller.install(hookBinaryURL: binary, settingsURL: settingsURL)

        let object = try readJSONObject(settingsURL)
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let notification = try XCTUnwrap(hooks["Notification"] as? [[String: Any]])
        XCTAssertEqual(notification.count, 3, "re-installing must not duplicate Notification entries")
    }

    func testRepairUpdatesOldPathAndDetectsMissingEvents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        let old = URL(fileURLWithPath: "/tmp/old/AgentClaudeHook")
        let current = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentClaudeHook")
        try ClaudeHookInstaller.install(hookBinaryURL: old, settingsURL: file)
        XCTAssertTrue(ClaudeHookInstaller.containsHooks(settingsURL: file))
        XCTAssertFalse(ClaudeHookInstaller.isInstalled(hookBinaryURL: current, settingsURL: file))
        try ClaudeHookInstaller.install(hookBinaryURL: current, settingsURL: file)
        XCTAssertTrue(ClaudeHookInstaller.isInstalled(hookBinaryURL: current, settingsURL: file))
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("/tmp/old"))
        var object = try readJSONObject(file)
        var hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop"); object["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        XCTAssertFalse(ClaudeHookInstaller.isInstalled(hookBinaryURL: current, settingsURL: file))
    }

    func testMalformedHookMapIsNotOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let text = #"{"hooks":[],"other":"preserve"}"#
        try text.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ClaudeHookInstaller.install(hookBinaryURL: URL(fileURLWithPath: "/tmp/AgentClaudeHook"), settingsURL: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), text)
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
