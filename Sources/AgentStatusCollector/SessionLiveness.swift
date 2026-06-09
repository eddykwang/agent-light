import Foundation

/// Checks whether a file is currently held open by a live process.
public protocol ProcessChecker {
    func isFileOpen(path: String) -> Bool
    func claudeCodeProcessCount(workspacePath: String) -> Int
}

public extension ProcessChecker {
    func claudeCodeProcessCount(workspacePath: String) -> Int { 0 }
}

/// Uses `lsof -t` to check if any process has the file open.
/// Fast for Codex (holds rollout files open with write descriptors).
/// Unreliable for CC (claude closes the transcript between writes) — use mtime instead.
public struct LsofProcessChecker: ProcessChecker {
    public init() {}

    public func isFileOpen(path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-t", "--", path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func claudeCodeProcessCount(workspacePath: String) -> Int {
        let workspace = Self.normalizedPath(workspacePath)
        guard !workspace.isEmpty else { return 0 }

        return claudeCodeCwds().filter { $0 == workspace }.count
    }

    /// Normalized cwds of all live `claude` processes, via one `pgrep` + one batched `lsof`.
    /// `lsof` costs ~0.3s per invocation, so querying every pid in a single call (instead of one
    /// call per pid) is what keeps the collector cycle short.
    private func claudeCodeCwds() -> [String] {
        let pids = claudeCodePIDs()
        guard !pids.isEmpty else { return [] }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "cwd", "-Fn"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()

        return output.split(separator: "\n")
            .filter { $0.hasPrefix("n") }
            .map { Self.normalizedPath(String($0.dropFirst())) }
    }

    private func claudeCodePIDs() -> [Int32] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-if", "claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()

        let selfPID = ProcessInfo.processInfo.processIdentifier
        return output.split(separator: "\n").compactMap { line in
            guard let pid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)),
                  pid != selfPID else { return nil }
            return pid
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        return normalized == "/" ? normalized : normalized.trimmingTrailingSlashes()
    }
}

/// Determines session liveness using provider-appropriate strategies:
/// - Codex: lsof open-handle check (codex keeps rollout files open)
/// - Claude Code: mtime recency check (claude closes transcript between writes)
/// - Fallback: mtime recency for unrecognized providers or when lsof fails
public struct LsofLivenessFilter: LivenessFilter {
    private let checker: ProcessChecker
    private let now: () -> Date
    /// How long a CC working session stays "alive" after its last file write (seconds).
    private let ccActiveStaleAfter: TimeInterval
    /// How long a CC session stays "alive" after its last file write (seconds).
    private let ccStaleAfter: TimeInterval
    /// Fallback staleness for Codex sessions when lsof fails (seconds).
    private let fallbackStaleAfter: TimeInterval

    public init(
        checker: ProcessChecker = LsofProcessChecker(),
        now: @escaping () -> Date = Date.init,
        ccActiveStaleAfter: TimeInterval = 60,
        ccStaleAfter: TimeInterval = 300,
        fallbackStaleAfter: TimeInterval = 300
    ) {
        self.checker = checker
        self.now = now
        self.ccActiveStaleAfter = ccActiveStaleAfter
        self.ccStaleAfter = ccStaleAfter
        self.fallbackStaleAfter = fallbackStaleAfter
    }

    public func aliveSessions(from sessions: [RawSession]) -> [RawSession] {
        let currentTime = now()
        let ccWorkingIDs = liveClaudeCodeWorkingSessionIDs(from: sessions, now: currentTime)
        return sessions.filter { session in
            isAlive(session: session, now: currentTime, ccWorkingIDs: ccWorkingIDs)
        }
    }

    private func isAlive(session: RawSession, now: Date, ccWorkingIDs: Set<String>) -> Bool {
        switch session.provider {
        case "claude-code":
            if session.isEventSignal {
                return true
            }
            if session.status == .working {
                return ccWorkingIDs.contains(session.id)
            }
            if session.status == .needsInput,
               checker.claudeCodeProcessCount(workspacePath: session.workspacePath) > 0 {
                return true
            }

            return now.timeIntervalSince(session.updatedAt) <= ccStaleAfter

        default:
            // Codex (and others): try lsof open-handle first
            if checker.isFileOpen(path: session.fileURL.path) {
                return true // process alive → keep regardless of age
            }
            // lsof returned empty: either process died or lsof failed
            // Fall back to mtime as safety net
            return now.timeIntervalSince(session.updatedAt) <= fallbackStaleAfter
        }
    }

    private func liveClaudeCodeWorkingSessionIDs(from sessions: [RawSession], now: Date) -> Set<String> {
        var liveIDs: Set<String> = []
        let workingSessions = sessions.filter { $0.provider == "claude-code" && $0.status == .working }
        let byWorkspace = Dictionary(grouping: workingSessions, by: { Self.normalizedWorkspacePath($0.workspacePath) })

        for (workspace, sessions) in byWorkspace {
            let sorted = sessions.sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            let recent = sorted.filter { now.timeIntervalSince($0.updatedAt) <= ccActiveStaleAfter }
            liveIDs.formUnion(recent.map(\.id))

            let processCount = checker.claudeCodeProcessCount(workspacePath: workspace)
            let remainingSlots = max(0, processCount - recent.count)
            guard remainingSlots > 0 else { continue }

            let stale = sorted.filter { now.timeIntervalSince($0.updatedAt) > ccActiveStaleAfter }
            liveIDs.formUnion(stale.prefix(remainingSlots).map(\.id))
        }

        return liveIDs
    }

    private static func normalizedWorkspacePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        return normalized == "/" ? normalized : normalized.trimmingTrailingSlashes()
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
