import XCTest
@testable import AgentTrafficLightsCore

final class StatusFileWriterTests: XCTestCase {
    func testWritesAtomicallyAndReparses() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("status.json").path

        let snapshot = StatusSnapshot(version: 1, updatedAt: Date(timeIntervalSince1970: 1_000_000), sessions: [
            AgentSession(id: "a", provider: "codex", projectName: "proj", status: .working,
                         detail: "x", workspacePath: "/tmp/proj", threadURL: nil, updatedAt: Date(timeIntervalSince1970: 1_000_000))
        ])

        let writer = StatusFileWriter()
        try writer.write(snapshot, to: path)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusSnapshot.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions.first?.status, .working)
        // no temp files left behind
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("status.") && $0 != "status.json" }
        XCTAssertTrue(leftovers.isEmpty)
    }
}
