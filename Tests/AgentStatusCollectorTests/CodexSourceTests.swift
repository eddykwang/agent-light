import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class CodexSourceTests: XCTestCase {
    func testDerivesSessionFromRolloutFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions/2026/06/06")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-2026-abc.jsonl")

        // Write a minimal valid rollout: session_meta (first line) + task_started
        let lines = [
            #"{"type":"session_meta","payload":{"id":"sid1","cwd":"/tmp/agent-light-demo/demo","thread_source":"user","originator":"codex-tui"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#
        ].joined(separator: "\n")
        try lines.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: root.appendingPathComponent("sessions").path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.provider, "codex")
        XCTAssertEqual(sessions.first?.workspacePath, "/tmp/agent-light-demo/demo")
        XCTAssertEqual(sessions.first?.status, .working)
        XCTAssertEqual(sessions.first?.id, "sid1")
        XCTAssertEqual(sessions.first?.fileURL, jsonl)
    }

    func testSkipsGuardianSubagentRollouts() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-guardian.jsonl")

        // Guardian rollout with thread_source = "subagent"
        let line = #"{"type":"session_meta","payload":{"id":"g1","cwd":"/tmp","thread_source":"subagent"}}"#
        try line.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: sessionsDir.path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 0, "guardian rollouts must be skipped")
    }

    func testSkipsGuardianSourcePayloadRollouts() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-guardian-source.jsonl")

        let lines = [
            #"{"type":"session_meta","payload":{"id":"g2","cwd":"/tmp","thread_source":"user","source":{"subagent":"reviewer"}}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#
        ].joined(separator: "\n")
        try lines.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: sessionsDir.path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 0, "guardian source payload rollouts must be skipped")
    }

    func testSkipsRolloutsWithoutSessionMeta() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-bad.jsonl")

        // No session_meta — should be skipped
        let line = #"{"type":"event_msg","payload":{"type":"task_started"}}"#
        try line.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: sessionsDir.path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 0, "rollouts without session_meta must be skipped")
    }

    func testSkipsStaleRolloutsBeforeClassification() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-stale.jsonl")

        let lines = [
            #"{"type":"session_meta","payload":{"id":"old","cwd":"/tmp/agent-light-demo/old","thread_source":"user"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#
        ].joined(separator: "\n")
        try lines.write(to: jsonl, atomically: true, encoding: .utf8)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: jsonl.path)

        let source = CodexRolloutSource(
            sessionsRoot: sessionsDir.path,
            now: { Date(timeIntervalSince1970: 10_000) },
            candidateStaleAfter: 300
        )
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 0)
    }

    func testReusesCachedSessionWhenFileSignatureIsUnchanged() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-cached.jsonl")

        let lines = [
            #"{"type":"session_meta","payload":{"id":"cached","cwd":"/tmp/agent-light-demo/cached","thread_source":"user"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#
        ].joined(separator: "\n")
        try lines.write(to: jsonl, atomically: true, encoding: .utf8)
        let fixedDate = Date(timeIntervalSince1970: 2_000)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: jsonl.path)

        let source = CodexRolloutSource(
            sessionsRoot: sessionsDir.path,
            now: { Date(timeIntervalSince1970: 2_100) },
            candidateStaleAfter: 300
        )
        XCTAssertEqual(try source.currentSessions().first?.id, "cached")

        try String(repeating: "x", count: lines.utf8.count).write(to: jsonl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: jsonl.path)

        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.first?.id, "cached")
        XCTAssertEqual(sessions.first?.status, .working)
    }

    func testIdleRolloutClassifiesAsIdle() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-idle.jsonl")

        let lines = [
            #"{"type":"session_meta","payload":{"id":"sid2","cwd":"/tmp/agent-light-demo/proj","thread_source":"user"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"#
        ].joined(separator: "\n")
        try lines.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: sessionsDir.path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.status, .idle)
    }

    func testLongRunningTurnClassifiesAsWorkingWhenLifecycleIsOutsideRecentTail() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-long-running.jsonl")

        var lines = [
            #"{"type":"session_meta","payload":{"id":"sid-long","cwd":"/tmp/agent-light-demo/long","thread_source":"user"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#
        ]
        lines.append(contentsOf: (1...150).map { #"{"type":"event_msg","payload":{"type":"token_count","total":"# + "\($0)" + #"}}"# })
        try lines.joined(separator: "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: sessionsDir.path)
        let sessions = try source.currentSessions()

        XCTAssertEqual(sessions.first?.status, .working)
    }

    func testProjectNameDerivedFromCwd() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonl = sessionsDir.appendingPathComponent("rollout-proj.jsonl")

        let lines = [
            #"{"type":"session_meta","payload":{"id":"sid3","cwd":"/tmp/agent-light-demo/myproject","thread_source":"user"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
        ].joined(separator: "\n")
        try lines.write(to: jsonl, atomically: true, encoding: .utf8)

        let source = CodexRolloutSource(sessionsRoot: sessionsDir.path)
        let sessions = try source.currentSessions()
        XCTAssertEqual(sessions.first?.projectName, "myproject")
    }
}
