import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class ClaudeCodeSourceTests: XCTestCase {
    func testDerivesSessionFromProjectsDir() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let projDir = root.appendingPathComponent("projects/-Users-me-demo")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = projDir.appendingPathComponent("abc123.jsonl")
        // Simulate an idle session (end_turn stop_reason)
        let line = """
        {"type":"assistant","sessionId":"abc123","cwd":"/tmp/agent-light-demo/demo","timestamp":"2026-06-06T10:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"Done"}],"stop_reason":"end_turn"}}
        """
        try line.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = ClaudeCodeTranscriptSource(projectsRoot: root.appendingPathComponent("projects").path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.provider, "claude-code")
        XCTAssertEqual(sessions.first?.workspacePath, "/tmp/agent-light-demo/demo")
        XCTAssertEqual(sessions.first?.status, .idle)
        XCTAssertEqual(sessions.first?.fileURL, jsonl)
    }

    func testSkipsEmptyJsonlFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let projDir = root.appendingPathComponent("projects/proj1")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = projDir.appendingPathComponent("empty.jsonl")
        try "".write(to: jsonl, atomically: true, encoding: .utf8)

        let source = ClaudeCodeTranscriptSource(projectsRoot: root.appendingPathComponent("projects").path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 0)
    }

    func testProjectNameFallsBackToCwdLastComponent() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let projDir = root.appendingPathComponent("projects/some-proj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = projDir.appendingPathComponent("sess1.jsonl")
        let line = """
        {"type":"assistant","sessionId":"sess1","cwd":"/tmp/agent-light-demo/myproject","timestamp":"2026-06-06T10:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}],"stop_reason":"end_turn"}}
        """
        try line.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = ClaudeCodeTranscriptSource(projectsRoot: root.appendingPathComponent("projects").path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.first?.projectName, "myproject")
    }

    func testWorksWithMultipleSessions() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        for i in 1...3 {
            let projDir = root.appendingPathComponent("projects/proj\(i)")
            try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
            let jsonl = projDir.appendingPathComponent("sess\(i).jsonl")
            let line = """
            {"type":"assistant","sessionId":"sess\(i)","cwd":"/tmp/proj\(i)","timestamp":"2026-06-06T10:00:00Z","message":{"role":"assistant","content":[],"stop_reason":"end_turn"}}
            """
            try line.write(to: jsonl, atomically: true, encoding: .utf8)
        }

        let source = ClaudeCodeTranscriptSource(projectsRoot: root.appendingPathComponent("projects").path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 3)
    }
}
