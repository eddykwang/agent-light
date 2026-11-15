import Foundation
import AgentTrafficLightsCore

public struct CodexHookSource: SessionSource {
    private let eventsRoot: String
    private let now: () -> Date
    /// Signal files older than this are treated as orphaned (e.g. a crashed session that
    /// never fired SessionEnd) and are pruned from disk.
    private let pruneAfter: TimeInterval

    public init(
        eventsRoot: String? = nil,
        now: @escaping () -> Date = Date.init,
        pruneAfter: TimeInterval = 60 * 60 * 24
    ) {
        self.eventsRoot = eventsRoot
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/codex-hooks"
        self.now = now
        self.pruneAfter = pruneAfter
    }

    public func currentSessions() throws -> [RawSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: eventsRoot) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let currentTime = now()

        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { file in
                let fileURL = URL(fileURLWithPath: eventsRoot).appendingPathComponent(file)
                guard let data = try? Data(contentsOf: fileURL),
                      let state = try? decoder.decode(CodexHookEventState.self, from: data) else {
                    return nil
                }

                guard !state.sessionId.isEmpty, !state.workspacePath.isEmpty else {
                    return nil
                }

                // Prune orphaned signal files (crashed sessions that never sent SessionEnd).
                if currentTime.timeIntervalSince(state.endedAt ?? state.updatedAt) > (state.endedAt == nil ? pruneAfter : 60) {
                    try? fm.removeItem(at: fileURL)
                    return nil
                }

                return RawSession(
                    id: state.sessionId,
                    provider: "codex",
                    projectName: (state.workspacePath as NSString).lastPathComponent,
                    workspacePath: state.workspacePath,
                    threadURL: URL(string: "codex://threads/\(state.sessionId)"),
                    fileURL: fileURL,
                    status: state.status,
                    detail: state.detail,
                    updatedAt: state.updatedAt,
                    isEventSignal: true,
                    completedAt: state.completedAt
                )
            }
    }
}
