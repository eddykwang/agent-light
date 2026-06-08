import Foundation
import AgentTrafficLightsCore

public struct ClaudeCodeTranscriptSource: SessionSource {
    private let projectsRoot: String
    private let reader = TranscriptReader()

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
                let updatedAt = mtime(path: path, fm: fm)
                sessions.append(RawSession(
                    id: "claude-code:\(sessionId)",
                    provider: "claude-code",
                    projectName: cwd.isEmpty ? "Claude Code" : (cwd as NSString).lastPathComponent,
                    workspacePath: cwd.isEmpty ? dir : cwd,
                    threadURL: URL(fileURLWithPath: path), // transcript file as threadURL for now
                    fileURL: fileURL,
                    status: status,
                    detail: detail,
                    updatedAt: updatedAt
                ))
            }
        }
        return sessions
    }

    private func mtime(path: String, fm: FileManager) -> Date {
        ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? Date()
    }
}
