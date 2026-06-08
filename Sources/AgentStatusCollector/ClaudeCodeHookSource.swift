import Foundation
import AgentTrafficLightsCore

public struct ClaudeCodeHookSource: SessionSource {
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
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/claude-hooks"
        self.now = now
        self.pruneAfter = pruneAfter
    }

    public func currentSessions() throws -> [RawSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: eventsRoot) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let currentTime = now()

        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { file in
                let fileURL = URL(fileURLWithPath: eventsRoot).appendingPathComponent(file)
                guard let data = try? Data(contentsOf: fileURL),
                      let state = try? decoder.decode(ClaudeHookEventState.self, from: data),
                      !state.sessionId.isEmpty,
                      !state.workspacePath.isEmpty else {
                    return nil
                }

                // Prune orphaned signal files (crashed sessions that never sent SessionEnd).
                if currentTime.timeIntervalSince(state.updatedAt) > pruneAfter {
                    try? fm.removeItem(at: fileURL)
                    return nil
                }

                let transcriptURL = state.transcriptPath.map(URL.init(fileURLWithPath:))
                return RawSession(
                    id: "claude-code:\(state.sessionId)",
                    provider: "claude-code",
                    projectName: (state.workspacePath as NSString).lastPathComponent,
                    workspacePath: state.workspacePath,
                    threadURL: transcriptURL,
                    fileURL: fileURL,
                    status: state.status,
                    detail: state.detail,
                    updatedAt: state.updatedAt
                )
            }
    }
}
