import XCTest
@testable import AgentTrafficLights

final class CopilotHookInstallerTests: XCTestCase {
    func testInstallWritesIsolatedOfficialConfiguration() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooksURL = root.appendingPathComponent("hooks/agent-light.json")
        let binary = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentCopilotHook")

        try CopilotHookInstaller.install(hookBinaryURL: binary, hooksURL: hooksURL)

        XCTAssertEqual(CopilotHookInstaller.status(hookBinaryURL: binary, hooksURL: hooksURL), .installed)
        let json = try configuration(at: hooksURL)
        XCTAssertEqual((json["version"] as? NSNumber)?.intValue, 1)
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["agentStop"])
        XCTAssertNotNil(hooks["notification"])
        XCTAssertNil(hooks["preToolUse"])
        XCTAssertNil(hooks["permissionRequest"])

        let notification = try XCTUnwrap((hooks["notification"] as? [[String: Any]])?.first)
        XCTAssertEqual(notification["matcher"] as? String, "permission_prompt|elicitation_dialog")
        XCTAssertTrue((notification["bash"] as? String)?.contains("AgentCopilotHook' notification") == true)
    }

    func testInstallIsIdempotentAndStalePathNeedsReinstall() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooksURL = root.appendingPathComponent("agent-light.json")
        let oldBinary = URL(fileURLWithPath: "/Old/Agent Light.app/Contents/MacOS/AgentCopilotHook")
        let newBinary = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentCopilotHook")

        try CopilotHookInstaller.install(hookBinaryURL: oldBinary, hooksURL: hooksURL)
        XCTAssertEqual(CopilotHookInstaller.status(hookBinaryURL: newBinary, hooksURL: hooksURL), .needsReinstall)

        try CopilotHookInstaller.install(hookBinaryURL: newBinary, hooksURL: hooksURL)
        let once = try Data(contentsOf: hooksURL)
        try CopilotHookInstaller.install(hookBinaryURL: newBinary, hooksURL: hooksURL)
        XCTAssertEqual(try Data(contentsOf: hooksURL), once)
        XCTAssertEqual(CopilotHookInstaller.status(hookBinaryURL: newBinary, hooksURL: hooksURL), .installed)
    }

    func testConflictIsNeverOverwrittenOrRemoved() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooksURL = root.appendingPathComponent("agent-light.json")
        let original = Data(#"{"version":1,"hooks":{"sessionStart":[{"bash":"other-tool"}]}}"#.utf8)
        try original.write(to: hooksURL)
        let binary = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentCopilotHook")

        XCTAssertEqual(CopilotHookInstaller.status(hookBinaryURL: binary, hooksURL: hooksURL), .conflict)
        XCTAssertThrowsError(try CopilotHookInstaller.install(hookBinaryURL: binary, hooksURL: hooksURL))
        XCTAssertThrowsError(try CopilotHookInstaller.remove(hooksURL: hooksURL, eventsRoot: root))
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    func testRemoveDeletesOnlyOwnedHookAndJSONStateFiles() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooksURL = root.appendingPathComponent("config/agent-light.json")
        let eventsRoot = root.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: eventsRoot, withIntermediateDirectories: true)
        try Data().write(to: eventsRoot.appendingPathComponent("state.json"))
        try Data().write(to: eventsRoot.appendingPathComponent("keep.txt"))
        let binary = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentCopilotHook")
        try CopilotHookInstaller.install(hookBinaryURL: binary, hooksURL: hooksURL)

        try CopilotHookInstaller.remove(hooksURL: hooksURL, eventsRoot: eventsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: hooksURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsRoot.appendingPathComponent("state.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventsRoot.appendingPathComponent("keep.txt").path))
    }

    func testShellQuotesSingleQuoteInBundlePath() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooksURL = root.appendingPathComponent("agent-light.json")
        let binary = URL(fileURLWithPath: "/Applications/Agent's Light.app/Contents/MacOS/AgentCopilotHook")
        try CopilotHookInstaller.install(hookBinaryURL: binary, hooksURL: hooksURL)

        let hooks = try XCTUnwrap(try configuration(at: hooksURL)["hooks"] as? [String: Any])
        let entries = try XCTUnwrap(hooks["agentStop"] as? [[String: Any]])
        XCTAssertTrue((entries.first?["bash"] as? String)?.contains("'\\''") == true)
    }

    private func makeDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func configuration(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
