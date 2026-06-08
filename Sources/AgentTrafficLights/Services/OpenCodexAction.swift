import AgentTrafficLightsCore
import AppKit
import Foundation

struct OpenCodexAction {
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func canOpen(_ session: AgentSession) -> Bool {
        urlToOpen(for: session) != nil
    }

    func urlToOpen(for session: AgentSession) -> URL? {
        if session.provider == "claude-code",
           let workspacePath = session.workspacePath,
           let directoryURL = safeDirectory(workspacePath) {
            return directoryURL
        }

        if let threadURL = session.threadURL, isAllowed(threadURL) {
            return threadURL
        }

        if let workspacePath = session.workspacePath,
           let directoryURL = safeDirectory(workspacePath) {
            return directoryURL
        }

        return nil
    }

    func open(_ session: AgentSession) {
        guard let url = urlToOpen(for: session) else { return }

        openURL(url)
    }

    private func isAllowed(_ url: URL) -> Bool {
        switch url.scheme {
        case "codex":
            return true
        case "file":
            return safeDirectory(url.path) != nil
        default:
            return false
        }
    }

    private func safeDirectory(_ path: String) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let blockedExtensions: Set<String> = ["app", "command", "tool", "scpt"]
        let pathExtension = (path as NSString).pathExtension.lowercased()
        guard !blockedExtensions.contains(pathExtension) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }
}
