import Foundation
import AgentTrafficLightsCore

public struct CodexRolloutSource: SessionSource {
    private let sessionsRoot: String
    private let reader = TranscriptReader()
    private let now: () -> Date
    private let candidateStaleAfter: TimeInterval
    private let cache = SourceCache()

    public init(
        sessionsRoot: String? = nil,
        now: @escaping () -> Date = Date.init,
        candidateStaleAfter: TimeInterval = 60 * 60
    ) {
        self.sessionsRoot = sessionsRoot
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/sessions"
        self.now = now
        self.candidateStaleAfter = candidateStaleAfter
    }

    public func currentSessions() throws -> [RawSession] {
        let fm = FileManager.default
        guard let entries = try? fm.subpathsOfDirectory(atPath: sessionsRoot) else { return [] }
        var sessions: [RawSession] = []
        for entry in entries where entry.hasSuffix(".jsonl") {
            let path = "\(sessionsRoot)/\(entry)"
            let fileURL = URL(fileURLWithPath: path)
            guard let signature = fileSignature(path: path, fm: fm),
                  let updatedAt = signature.modificationDate else { continue }
            guard now().timeIntervalSince(updatedAt) <= candidateStaleAfter else { continue }

            if let cached = cache.session(path: path, signature: signature) {
                sessions.append(cached)
                continue
            }

            // Read session_meta FIRST so we can apply the guardian filter before
            // loading the (potentially large) rest of the rollout file.
            guard let firstLine = try? reader.firstObject(path: path),
                  (firstLine["type"] as? String) == "session_meta",
                  let payload = firstLine["payload"] as? [String: Any] else { continue }

            guard Self.isUserThread(payload) else { continue }

            // Only read the full rollout body for non-guardian sessions.
            let objects = (try? reader.lastObjects(
                path: path,
                limit: 100,
                extendingBackwardUntil: Self.isCodexLifecycleEvent
            )) ?? []
            guard !objects.isEmpty else { continue }

            let sessionId = payload["id"] as? String ?? (entry as NSString).lastPathComponent
            let cwd = payload["cwd"] as? String ?? ""
            let (status, detail) = StatusClassifier.classifyCodex(objects: objects)

            let session = RawSession(
                id: sessionId,
                provider: "codex",
                projectName: cwd.isEmpty ? "Codex" : (cwd as NSString).lastPathComponent,
                workspacePath: cwd.isEmpty ? sessionsRoot : cwd,
                threadURL: URL(string: "codex://threads/\(sessionId)"),
                fileURL: fileURL,
                status: status,
                detail: detail,
                updatedAt: updatedAt
            )
            cache.store(session, path: path, signature: signature)
            sessions.append(session)
        }
        return sessions
    }

    private func fileSignature(path: String, fm: FileManager) -> FileSignature? {
        guard let attributes = try? fm.attributesOfItem(atPath: path) else { return nil }
        return FileSignature(
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        )
    }

    private static func isUserThread(_ payload: [String: Any]) -> Bool {
        let threadSource = payload["thread_source"] as? String ?? ""
        guard threadSource == "user" else { return false }

        if let source = payload["source"] as? [String: Any],
           source["subagent"] != nil || source["guardian"] != nil {
            return false
        }

        return true
    }

    private static func isCodexLifecycleEvent(_ object: [String: Any]) -> Bool {
        guard (object["type"] as? String) == "event_msg",
              let payload = object["payload"] as? [String: Any],
              let eventType = payload["type"] as? String else {
            return false
        }
        return eventType == "task_started" || eventType == "task_complete" || eventType == "turn_aborted"
    }
}

private struct FileSignature: Equatable {
    let modificationDate: Date?
    let size: UInt64
}

private final class SourceCache {
    private struct Entry {
        let signature: FileSignature
        let session: RawSession
    }

    private var entries: [String: Entry] = [:]

    func session(path: String, signature: FileSignature) -> RawSession? {
        guard let entry = entries[path], entry.signature == signature else {
            return nil
        }
        return entry.session
    }

    func store(_ session: RawSession, path: String, signature: FileSignature) {
        entries[path] = Entry(signature: signature, session: session)
    }
}
