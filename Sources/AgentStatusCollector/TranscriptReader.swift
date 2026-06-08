import Foundation

public struct TranscriptReader {
    private static let newline = UInt8(ascii: "\n")
    private static let headReadLimit = 64 * 1024
    private static let tailChunkSize = 256 * 1024
    private static let tailReadLimit = 16 * 1024 * 1024

    public init() {}

    /// Returns the first parseable JSON object from a JSONL file, or nil if not found.
    /// Used to read `session_meta` (always the first line in Codex rollout files).
    public func firstObject(path: String) throws -> [String: Any]? {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }

        var data = Data()
        var newlineCount = 0
        while data.count < Self.headReadLimit, newlineCount < 5 {
            let chunk = try handle.read(upToCount: min(4096, Self.headReadLimit - data.count)) ?? Data()
            if chunk.isEmpty { break }
            newlineCount += chunk.filter { $0 == Self.newline }.count
            data.append(chunk)
        }

        for line in data.split(separator: Self.newline, omittingEmptySubsequences: true).prefix(5) {
            guard let obj = Self.parseObject(line) else { continue }
            return obj
        }
        return nil
    }

    /// Returns up to `limit` most-recent parseable JSON objects from a JSONL file, in file order.
    public func lastObjects(
        path: String,
        limit: Int,
        extendingBackwardUntil predicate: (([String: Any]) -> Bool)? = nil
    ) throws -> [[String: Any]] {
        guard limit > 0 else { return [] }

        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        var offset = fileSize
        var buffer = Data()
        var bytesRead = 0
        var reversedObjects: [[String: Any]] = []
        var satisfiedPredicate = predicate == nil

        while offset > 0, bytesRead < Self.tailReadLimit {
            let readSize = min(Self.tailChunkSize, Int(offset), Self.tailReadLimit - bytesRead)
            offset -= UInt64(readSize)
            try handle.seek(toOffset: offset)
            let chunk = try handle.read(upToCount: readSize) ?? Data()
            bytesRead += chunk.count
            buffer.insert(contentsOf: chunk, at: 0)

            let hasFileStart = offset == 0
            let parsed = Self.parseCompleteLines(fromTailBuffer: buffer, includesFileStart: hasFileStart)
            reversedObjects = []
            satisfiedPredicate = predicate == nil

            for obj in parsed.reversed() {
                reversedObjects.append(obj)
                if let predicate, reversedObjects.count >= limit, predicate(obj) {
                    satisfiedPredicate = true
                    break
                }
                if predicate == nil, reversedObjects.count >= limit {
                    break
                }
            }

            if reversedObjects.count >= limit, satisfiedPredicate {
                break
            }
        }

        return reversedObjects.reversed()
    }

    private static func parseCompleteLines(fromTailBuffer data: Data, includesFileStart: Bool) -> [[String: Any]] {
        var lines = data.split(separator: newline, omittingEmptySubsequences: true)
        if !includesFileStart, data.first != newline, !lines.isEmpty {
            lines.removeFirst()
        }
        return lines.compactMap(parseObject)
    }

    private static func parseObject(_ line: Data.SubSequence) -> [String: Any]? {
        let data = Data(line)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
