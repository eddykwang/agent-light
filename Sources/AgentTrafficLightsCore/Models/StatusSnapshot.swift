import Foundation

public struct StatusSnapshot: Codable, Equatable {
    public let version: Int
    public let updatedAt: Date?
    public let sessions: [AgentSession]

    public init(version: Int, updatedAt: Date?, sessions: [AgentSession]) {
        self.version = version
        self.updatedAt = updatedAt
        self.sessions = sessions
    }

    public var aggregateStatus: AgentStatus {
        guard !sessions.isEmpty else {
            return .idle
        }

        let statuses = sessions.map(\.status)

        if statuses.contains(.failed) {
            return .failed
        }

        if statuses.contains(.needsInput) {
            return .needsInput
        }

        if statuses.contains(.working) {
            return .working
        }

        if statuses.contains(.idle) {
            return .idle
        }

        return .unknown
    }

    public func visibleSessions(limit: Int) -> [AgentSession] {
        Array(
            sessions
                .sorted { lhs, rhs in
                    let left = lhs.updatedAt ?? .distantPast
                    let right = rhs.updatedAt ?? .distantPast
                    return left > right
                }
                .prefix(limit)
        )
    }
}
