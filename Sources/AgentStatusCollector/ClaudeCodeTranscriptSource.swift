import Foundation
import AgentTrafficLightsCore

public struct ClaudeCodeTranscriptSource: SessionSource {
    private let projectsRoot: String
    private let reader = TranscriptReader()
    private let cache = SourceCache()

    public init(projectsRoot: String? = nil) {
        self.projectsRoot = projectsRoot
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/projects"
    }

    public func currentSessions() throws -> [RawSession] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsRoot) else { return [] }
        var sessions: [RawSession] = []
        for proj in projectDirs {
            let dir = "\(projectsRoot)/\(proj)"
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = "\(dir)/\(file)"
                let fileURL = URL(fileURLWithPath: path)

                // Reading + classifying the transcript is the expensive per-tick work. Skip it
                // when the file is byte-for-byte unchanged (mtime + size) since the last scan —
                // this keeps the collector cycle short when many transcripts are idle.
                guard let signature = fileSignature(path: path, fm: fm) else { continue }
                if let cached = cache.session(path: path, signature: signature) {
                    sessions.append(cached)
                    continue
                }

                let objects = (try? reader.lastObjects(path: path, limit: 50)) ?? []
                guard !objects.isEmpty else { continue }
                let (status, detail) = StatusClassifier.classifyClaudeCode(objects: objects)
                // Extract session metadata from entries (skip queue-operation which lacks cwd)
                let cwd = objects.reversed()
                    .compactMap { obj -> String? in
                        guard (obj["type"] as? String) != "queue-operation" else { return nil }
                        return obj["cwd"] as? String
                    }.first ?? ""
                // Also skip queue-operation for sessionId (consistent with cwd extraction)
                let sessionId = objects.reversed()
                    .compactMap { obj -> String? in
                        guard (obj["type"] as? String) != "queue-operation" else { return nil }
                        return obj["sessionId"] as? String
                    }.first ?? (file as NSString).deletingPathExtension
                let session = RawSession(
                    id: "claude-code:\(sessionId)",
                    provider: "claude-code",
                    projectName: cwd.isEmpty ? "Claude Code" : (cwd as NSString).lastPathComponent,
                    workspacePath: cwd.isEmpty ? dir : cwd,
                    threadURL: URL(fileURLWithPath: path), // transcript file as threadURL for now
                    fileURL: fileURL,
                    status: status,
                    detail: detail,
                    updatedAt: signature.modificationDate ?? Date()
                )
                cache.store(session, path: path, signature: signature)
                sessions.append(session)
            }
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
