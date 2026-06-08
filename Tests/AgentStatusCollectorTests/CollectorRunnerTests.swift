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
                              updatedAt: Date(timeIntervalSince1970: 10))
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
        // If a hook event was missed, the stale hook file must not mask the fresher transcript state.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let staleHook = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                   workspacePath: "/tmp/p", threadURL: nil,
                                   fileURL: URL(fileURLWithPath: "/tmp/hook.json"),
                                   status: .idle, detail: "Stale hook idle",
                                   updatedAt: Date(timeIntervalSince1970: 5))
        let freshTranscript = RawSession(id: "claude-code:s1", provider: "claude-code", projectName: "p",
                                         workspacePath: "/tmp/p", threadURL: nil,
                                         fileURL: URL(fileURLWithPath: "/tmp/transcript.jsonl"),
                                         status: .working, detail: "Fresh transcript working",
                                         updatedAt: Date(timeIntervalSince1970: 20))
        let runner = CollectorRunner(
            sources: [StubSource(sessions: [staleHook]), StubSource(sessions: [freshTranscript])],
            liveness: AllAliveLiveness(),
            writer: StatusFileWriter(),
            statusPath: path,
            now: { Date(timeIntervalSince1970: 20) }
        )

        try runner.runOnce()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.status, .working)
        XCTAssertEqual(decoded.sessions.first?.detail, "Fresh transcript working")
    }
}

private struct StubSource: SessionSource {
    let sessions: [RawSession]
    func currentSessions() throws -> [RawSession] { sessions }
}
private struct AllAliveLiveness: LivenessFilter {
    func aliveSessions(from sessions: [RawSession]) -> [RawSession] { sessions }
}
