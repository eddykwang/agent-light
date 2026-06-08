import XCTest
@testable import AgentStatusCollector

final class TranscriptReaderTests: XCTestCase {
    func testReadsLastObjectsAndSkipsBadLines() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        try """
        {"type":"user","n":1}
        not json
        {"type":"assistant","n":2}
        """.write(to: file, atomically: true, encoding: .utf8)

        let objs = try TranscriptReader().lastObjects(path: file.path, limit: 5)
        XCTAssertEqual(objs.count, 2)
        XCTAssertEqual(objs.last?["type"] as? String, "assistant")
    }

    func testReturnsAtMostLimit() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        let lines = (1...10).map { "{\"n\":\($0)}" }.joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let objs = try TranscriptReader().lastObjects(path: file.path, limit: 3)
        XCTAssertEqual(objs.count, 3)
        XCTAssertEqual(objs.last?["n"] as? Int, 10)
        XCTAssertEqual(objs.first?["n"] as? Int, 8)
    }

    func testEmptyFileReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("empty.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let objs = try TranscriptReader().lastObjects(path: file.path, limit: 5)
        XCTAssertEqual(objs.count, 0)
    }

    func testThrowsForMissingFile() {
        XCTAssertThrowsError(try TranscriptReader().lastObjects(path: "/nonexistent/path.jsonl", limit: 5))
    }

    func testFirstObjectDoesNotDecodeEntireFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("large.jsonl")

        var data = Data(#"{"type":"session_meta","payload":{"thread_source":"user"}}"#.utf8)
        data.append(0x0A)
        data.append(contentsOf: [0xFF, 0xFE, 0xFD])
        try data.write(to: file)

        let obj = try TranscriptReader().firstObject(path: file.path)
        XCTAssertEqual(obj?["type"] as? String, "session_meta")
    }

    func testLastObjectsDoesNotDecodeEntireFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("large.jsonl")

        var data = Data([0xFF, 0xFE, 0xFD, 0x0A])
        data.append(Data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8))
        data.append(0x0A)
        data.append(Data(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#.utf8))
        try data.write(to: file)

        let objs = try TranscriptReader().lastObjects(path: file.path, limit: 2)
        XCTAssertEqual(objs.count, 2)
        XCTAssertEqual((objs.last?["payload"] as? [String: Any])?["type"] as? String, "task_complete")
    }
}
