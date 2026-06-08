import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class ClaudeCodeHookSourceTests: XCTestCase {
    func testReadsHookSessionState() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = root.appendingPathComponent("demo")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let transcript = workspace.appendingPathComponent("abc123.jsonl")
        let event = root.appendingPathComponent("abc123.json")
        let json = """
        {
          "version": 1,
          "sessionId": "abc123",
          "status": "needsInput",
          "detail": "Claude Code needs permission",
          "workspacePath": "\(workspace.path)",
          "transcriptPath": "\(transcript.path)",
          "updatedAt": "2026-06-07T17:00:00Z"
        }
        """
        try json.write(to: event, atomically: true, encoding: .utf8)

        let source = ClaudeCodeHookSource(
            eventsRoot: root.path,
            now: { Date(timeIntervalSince1970: 1_780_851_700) }
        )
        let sessions = try source.currentSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "claude-code:abc123")
        XCTAssertEqual(sessions.first?.provider, "claude-code")
        XCTAssertEqual(sessions.first?.projectName, "demo")
        XCTAssertEqual(sessions.first?.workspacePath, workspace.path)
        XCTAssertEqual(sessions.first?.status, .needsInput)
        XCTAssertEqual(sessions.first?.detail, "Claude Code needs permission")
        XCTAssertEqual(sessions.first?.threadURL, transcript)
    }

    func testPrunesOrphanedSignalFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let event = root.appendingPathComponent("orphan.json")
        let json = """
        {
          "version": 1,
          "sessionId": "orphan",
          "status": "needsInput",
          "detail": "Claude Code needs permission",
          "workspacePath": "/tmp/demo",
          "transcriptPath": null,
          "updatedAt": "2026-06-07T17:00:00Z"
        }
        """
        try json.write(to: event, atomically: true, encoding: .utf8)

        // now() is years after the file's updatedAt → well past the 24h prune window.
        let source = ClaudeCodeHookSource(
            eventsRoot: root.path,
            now: { Date(timeIntervalSince1970: 1_900_000_000) },
            pruneAfter: 60 * 60 * 24
        )

        XCTAssertEqual(try source.currentSessions(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: event.path), "orphaned file should be deleted")
    }

    func testSkipsMalformedHookFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "not json".write(to: root.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)

        let source = ClaudeCodeHookSource(eventsRoot: root.path)
        XCTAssertEqual(try source.currentSessions(), [])
    }
}
