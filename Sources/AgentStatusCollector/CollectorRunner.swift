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
    /// How much newer a transcript-derived entry must be (seconds) before it may override the
    /// hook event-signal for the same session. Protects the authoritative hook state from a
    /// transcript entry that merely raced ahead by a fraction of a second, while still letting a
    /// clearly-newer transcript recover when the hook source has gone stale.
    private let hookAuthorityGrace: TimeInterval

    public init(
        sources: [any SessionSource],
        liveness: LivenessFilter,
        writer: StatusFileWriter,
        statusPath: String,
        now: @escaping () -> Date = Date.init,
        hookAuthorityGrace: TimeInterval = 60
    ) {
        self.sources = sources
        self.liveness = liveness
        self.writer = writer
        self.statusPath = statusPath
        self.now = now
        self.hookAuthorityGrace = hookAuthorityGrace
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

    /// Collapses sessions sharing an id to one.
    ///
    /// When the hook source and transcript source both report the same session, the hook wins.
    /// The hook event-signal is the authoritative real-time lifecycle state — it knows
    /// `working`/`needsInput`/`idle` the instant the event fires. The transcript classifier is a
    /// lagging heuristic over file contents: while the model is mid-think it still reads the
    /// previous turn's `end_turn` as `idle`, and its mtime can race a fraction of a second ahead
    /// of the hook, so plain recency would let a stale transcript `idle` override a correct hook
    /// `working` (and likewise mask `needsInput`/`failed`, which the transcript can't represent).
    ///
    /// The transcript only takes over as a fallback when it is newer than the hook by more than
    /// `hookAuthorityGrace` — i.e. the hook source has genuinely gone stale. Ties keep the first
    /// occurrence (the hook source, listed first).
    private func deduplicateByID(_ sessions: [RawSession]) -> [RawSession] {
        var indexByID: [String: Int] = [:]
        var result: [RawSession] = []
        for session in sessions {
            if let index = indexByID[session.id] {
                // The completion marker is independent of status, so preserve the latest one
                // regardless of which source wins the status field.
                let mergedCompletedAt = latest(result[index].completedAt, session.completedAt)
                let winner = shouldReplace(existing: result[index], with: session) ? session : result[index]
                result[index] = winner.withCompletedAt(mergedCompletedAt)
            } else {
                indexByID[session.id] = result.count
                result.append(session)
            }
        }
        return result
    }

    private func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): return max(l, r)
        default: return lhs ?? rhs
        }
    }

    private func shouldReplace(existing: RawSession, with candidate: RawSession) -> Bool {
        // Hook event-signal vs transcript-derived entry: the hook is authoritative, so keep it
        // unless the transcript has moved clearly ahead in time (the hook source has gone stale).
        if existing.isEventSignal && !candidate.isEventSignal {
            return candidate.updatedAt.timeIntervalSince(existing.updatedAt) > hookAuthorityGrace
        }
        if candidate.isEventSignal && !existing.isEventSignal {
            return existing.updatedAt.timeIntervalSince(candidate.updatedAt) <= hookAuthorityGrace
        }

        // Same source class: plain recency, ties keep existing.
        return candidate.updatedAt > existing.updatedAt
    }
}
