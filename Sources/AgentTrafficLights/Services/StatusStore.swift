import AgentTrafficLightsCore
import Combine
import Foundation

@MainActor
final class StatusStore: ObservableObject {
    nonisolated static let defaultFileStaleAfter: TimeInterval = 60 * 60 * 24 * 7

    @Published private(set) var aggregateStatus: AgentStatus = .unknown
    @Published private(set) var visibleSessions: [AgentSession] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var message: String = "No status file loaded"

    private let parser: StatusParser
    private let now: () -> Date
    private let staleAfter: TimeInterval
    private var lastFileSignature: FileSignature?

    init(
        parser: StatusParser = StatusParser(),
        now: @escaping () -> Date = Date.init,
        staleAfter: TimeInterval = StatusStore.defaultFileStaleAfter
    ) {
        self.parser = parser
        self.now = now
        self.staleAfter = staleAfter
    }

    func reload(from path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            lastFileSignature = nil
            publish(aggregateStatus: .unknown, visibleSessions: [], lastUpdated: nil, message: "Status file not found")
            return
        }

        do {
            let fileSignature = try FileSignature(path: path)
            if fileSignature == lastFileSignature {
                return
            }

            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            switch parser.parse(data: data) {
            case .success(let snapshot):
                lastFileSignature = fileSignature

                if let updatedAt = snapshot.updatedAt, now().timeIntervalSince(updatedAt) > staleAfter {
                    publish(aggregateStatus: .unknown, visibleSessions: [], lastUpdated: updatedAt, message: "Status file is stale")
                    return
                }

                let sessionCount = snapshot.sessions.count
                let sessionMessage = sessionCount == 1 ? "1 agent session" : "\(sessionCount) agent sessions"
                publish(
                    aggregateStatus: snapshot.aggregateStatus,
                    visibleSessions: snapshot.visibleSessions(limit: 5),
                    lastUpdated: snapshot.updatedAt,
                    message: snapshot.sessions.isEmpty ? "No active agent sessions" : sessionMessage
                )
            case .failure(let error):
                lastFileSignature = nil
                publish(aggregateStatus: .unknown, visibleSessions: [], lastUpdated: nil, message: "Invalid status JSON: \(error.localizedDescription)")
            }
        } catch {
            lastFileSignature = nil
            publish(aggregateStatus: .unknown, visibleSessions: [], lastUpdated: nil, message: "Could not read status file: \(error.localizedDescription)")
        }
    }

    private func publish(
        aggregateStatus: AgentStatus,
        visibleSessions: [AgentSession],
        lastUpdated: Date?,
        message: String
    ) {
        guard self.aggregateStatus != aggregateStatus
            || self.visibleSessions != visibleSessions
            || self.lastUpdated != lastUpdated
            || self.message != message
        else {
            return
        }

        self.aggregateStatus = aggregateStatus
        self.visibleSessions = visibleSessions
        self.lastUpdated = lastUpdated
        self.message = message
    }
}

private struct FileSignature: Equatable {
    let modificationDate: Date?
    let size: UInt64

    init(path: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        self.modificationDate = attributes[.modificationDate] as? Date
        self.size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
