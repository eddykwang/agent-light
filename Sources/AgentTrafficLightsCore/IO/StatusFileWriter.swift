import Foundation

public struct StatusFileWriter {
    public init() {}

    public func write(_ snapshot: StatusSnapshot, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let tmp = dir.appendingPathComponent("status.\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tmp) } // safety net: clean up tmp on failure
        try data.write(to: tmp) // tmp is a staging file; replaceItemAt provides the atomic swap
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
