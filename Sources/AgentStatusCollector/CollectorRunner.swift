import Foundation
import AgentTrafficLightsCore

public protocol LivenessFilter {
    func aliveSessions(from sessions: [RawSession]) -> [RawSession]
}

public final class CollectorRunner {
    private let sources: [any SessionSource]
    private let liveness: LivenessFilter
    private let writer: StatusFileWriter
    private let statusPath: String
    private let now: () -> Date

    public init(
        sources: [any SessionSource],
        liveness: LivenessFilter,
        writer: StatusFileWriter,
        statusPath: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.sources = sources
        self.liveness = liveness
        self.writer = writer
        self.statusPath = statusPath
        self.now = now
    }

    public func runOnce() throws {
        var raw: [RawSession] = []
        for source in sources {
            raw.append(contentsOf: (try? source.currentSessions()) ?? [])
        }
        let alive = deduplicateByID(liveness.aliveSessions(from: raw))
        let snapshot = StatusSnapshot(version: 1, updatedAt: now(), sessions: alive.map { $0.toAgentSession() })
        try writer.write(snapshot, to: statusPath)
    }

    /// Collapses sessions sharing an id to one. When the hook source and transcript source both
    /// report the same session, the entry with the newer `updatedAt` wins — so a missed hook
    /// event lets the fresher transcript state take over instead of a stale hook state masking it.
    /// Ties keep the first occurrence (the hook source, which is listed first and is more precise).
    private func deduplicateByID(_ sessions: [RawSession]) -> [RawSession] {
        var indexByID: [String: Int] = [:]
        var result: [RawSession] = []
        for session in sessions {
            if let index = indexByID[session.id] {
                if session.updatedAt > result[index].updatedAt {
                    result[index] = session
                }
            } else {
                indexByID[session.id] = result.count
                result.append(session)
            }
        }
        return result
    }
}
