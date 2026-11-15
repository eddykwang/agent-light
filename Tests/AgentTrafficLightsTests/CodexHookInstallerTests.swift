import XCTest
@testable import AgentTrafficLights

final class CodexHookInstallerTests: XCTestCase {
    private let binary = URL(fileURLWithPath: "/Applications/Agent Light.app/Contents/MacOS/AgentCodexHook")

    func testInstallRepairAndRemovePreserveOtherHooksAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("hooks.json")
        try #"{"description":"existing","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other"}]}]}}"#.write(to: file, atomically: true, encoding: .utf8)
        let old = URL(fileURLWithPath: "/tmp/old/AgentCodexHook")
        try CodexHookInstaller.install(hookBinaryURL: old, hooksURL: file)
        XCTAssertEqual(CodexHookInstaller.status(hookBinaryURL: binary, hooksURL: file), .needsReinstall)
        try CodexHookInstaller.install(hookBinaryURL: binary, hooksURL: file)
        let once = try Data(contentsOf: file)
        try CodexHookInstaller.install(hookBinaryURL: binary, hooksURL: file)
        XCTAssertEqual(once, try Data(contentsOf: file))
        XCTAssertEqual(CodexHookInstaller.status(hookBinaryURL: binary, hooksURL: file), .configured)
        let text = String(decoding: once, as: UTF8.self)
        XCTAssertFalse(text.contains("/tmp/old"))
        XCTAssertTrue(text.contains("PermissionRequest"))
        XCTAssertTrue(text.contains("Interrupt"))
        try CodexHookInstaller.remove(hooksURL: file, eventsRoot: root.appendingPathComponent("events"))
        let remaining = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertTrue(remaining.contains("echo other"))
        XCTAssertTrue(remaining.contains("existing"))
        XCTAssertFalse(remaining.contains("AgentCodexHook"))
    }

    func testInvalidConfigurationIsNotOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        for text in ["not json", "[]", #"{"hooks":{"Stop":"invalid"}}"#] {
            try text.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try CodexHookInstaller.install(hookBinaryURL: binary, hooksURL: file))
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), text)
            XCTAssertEqual(CodexHookInstaller.status(hookBinaryURL: binary, hooksURL: file), .invalidConfiguration)
        }
    }
}
