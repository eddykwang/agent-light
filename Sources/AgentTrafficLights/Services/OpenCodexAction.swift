import AgentTrafficLightsCore
import AppKit
import Foundation

struct OpenCodexAction {
    var openURL: (URL) -> Void
    var canOpenApplication: (URL) -> Bool

    init(
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        canOpenApplication: @escaping (URL) -> Bool = { NSWorkspace.shared.urlForApplication(toOpen: $0) != nil }
    ) {
        self.openURL = openURL
        self.canOpenApplication = canOpenApplication
    }

    func threadURLToOpen(for session: AgentSession) -> URL? {
        if let threadURL = session.threadURL,
           isCodexThreadURL(threadURL),
           canOpenApplication(threadURL) {
            return threadURL
        }

        return nil
    }

    func folderURL(for session: AgentSession) -> URL? {
        guard let workspacePath = session.workspacePath else { return nil }
        return safeDirectory(workspacePath)
    }

    func openThread(_ session: AgentSession) {
        guard let url = threadURLToOpen(for: session) else { return }

        openURL(url)
    }

    func openFolder(_ session: AgentSession) {
        guard let url = folderURL(for: session) else { return }

        openURL(url)
    }

    private func isCodexThreadURL(_ url: URL) -> Bool {
        url.scheme == "codex"
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
