import XCTest
import AgentTrafficLightsCore
@testable import AgentStatusCollector

final class CollectorRunnerTests: XCTestCase {
    func testRunOnceWritesSessionsFromSources() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let raw = RawSession(id: "s1", provider: "codex", projectName: "p", workspacePath: "/tmp/p",
                             threadURL: nil, fileURL: URL(fileURLWithPath: "/tmp/p.jsonl"), status: .working, detail: "d",
                             updatedAt: Date(timeIntervalSince1970: 5))
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [raw])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 5) }
        )
        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.map(\.id), ["s1"])
    }

    func testRunOnceKeepsFirstSourceWhenSessionIDsOverlap() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let hook = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                              workspacePath: "/tmp/p", threadURL: nil,
                              fileURL: URL(fileURLWithPath: "/tmp/hook.json"),
                              status: .needsInput, detail: "Hook state",
                              updatedAt: Date(timeIntervalSince1970: 10), isEventSignal: true)
        let transcript = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                    workspacePath: "/tmp/p", threadURL: nil,
                                    fileURL: URL(fileURLWithPath: "/tmp/transcript.jsonl"),
                                    status: .working, detail: "Transcript state",
                                    updatedAt: Date(timeIntervalSince1970: 9))
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [hook]), StubSource(sessions: [transcript])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 10) }
        )

        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.status, .needsInput)
        XCTAssertEqual(decoded.sessions.first?.detail, "Hook state")
    }

    func testFresherTranscriptOverridesStaleHookState() throws {
        // If the hook source has gone stale (clearly older than the transcript), the transcript
        // takes over so a dead hook file can't mask the live transcript state.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let staleHook = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                   workspacePath: "/tmp/p", threadURL: nil,
                                   fileURL: URL(fileURLWithPath: "/tmp/hook.json"),
                                   status: .idle, detail: "Stale hook idle",
                                   updatedAt: Date(timeIntervalSince1970: 5), isEventSignal: true)
        let freshTranscript = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                         workspacePath: "/tmp/p", threadURL: nil,
                                         fileURL: URL(fileURLWithPath: "/tmp/transcript.jsonl"),
                                         status: .working, detail: "Fresh transcript working",
                                         updatedAt: Date(timeIntervalSince1970: 200))
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [staleHook]), StubSource(sessions: [freshTranscript])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 200) }
        )

        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.status, .working)
        XCTAssertEqual(decoded.sessions.first?.detail, "Fresh transcript working")
    }

    func testMergePreservesHookCompletedAtWhenTranscriptWinsStatus() throws {
        // When the hook has gone stale and the transcript wins the status field, the hook's
        // completedAt must still survive the merge so the app can fire the completion notification.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let stopAt = Date(timeIntervalSince1970: 9)
        let hook = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                              workspacePath: "/tmp/p", threadURL: nil,
                              fileURL: URL(fileURLWithPath: "/tmp/hook.json"),
                              status: .idle, detail: "Hook stop",
                              updatedAt: stopAt, isEventSignal: true, completedAt: stopAt)
        let transcript = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                    workspacePath: "/tmp/p", threadURL: nil,
                                    fileURL: URL(fileURLWithPath: "/tmp/transcript.jsonl"),
                                    status: .idle, detail: "Transcript idle",
                                    updatedAt: Date(timeIntervalSince1970: 200), completedAt: nil)
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [hook]), StubSource(sessions: [transcript])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 200) }
        )

        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.detail, "Transcript idle")
        XCTAssertEqual(decoded.sessions.first?.completedAt, stopAt)
    }

    func testTranscriptWorkingDoesNotMaskNearbyHookNeedsInput() throws {
        // Race: the transcript mtime advances a hair past the permission hook event.
        // The transcript source cannot represent needsInput, so a marginally-newer
        // "working" must NOT override a fresh hook "needsInput".
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let hook = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                              workspacePath: "/tmp/p", threadURL: nil,
                              fileURL: URL(fileURLWithPath: "/tmp/hook.json"),
                              status: .needsInput, detail: "Hook needs input",
                              updatedAt: Date(timeIntervalSince1970: 9), isEventSignal: true)
        let transcript = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                    workspacePath: "/tmp/p", threadURL: nil,
                                    fileURL: URL(fileURLWithPath: "/tmp/transcript.jsonl"),
                                    status: .working, detail: "Transcript working",
                                    updatedAt: Date(timeIntervalSince1970: 10))
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [hook]), StubSource(sessions: [transcript])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 10) }
        )

        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.status, .needsInput)
    }

    func testClearlyNewerTranscriptOverridesStaleHookNeedsInput() throws {
        // Fallback must survive: if the permission was answered but the PostToolUse hook
        // was missed, the stale needsInput signal must give way once the transcript has
        // clearly moved on (well past the grace window).
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let staleHook = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                   workspacePath: "/tmp/p", threadURL: nil,
                                   fileURL: URL(fileURLWithPath: "/tmp/hook.json"),
                                   status: .needsInput, detail: "Stale needs input",
                                   updatedAt: Date(timeIntervalSince1970: 5), isEventSignal: true)
        let freshTranscript = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                         workspacePath: "/tmp/p", threadURL: nil,
                                         fileURL: URL(fileURLWithPath: "/tmp/transcript.jsonl"),
                                         status: .working, detail: "Fresh transcript working",
                                         updatedAt: Date(timeIntervalSince1970: 200))
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [staleHook]), StubSource(sessions: [freshTranscript])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 200) }
        )

        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.status, .working)
    }
}

private struct StubSource: SessionSource {
    let sessions: [RawSession]
    func currentSessions() throws -> [RawSession] { sessions }
}
private struct AllAliveLiveness: LivenessFilter {
    func aliveSessions(from sessions: [RawSession]) -> [RawSession] { sessions }
}
