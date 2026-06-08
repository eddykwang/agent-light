import Foundation

@MainActor
final class CollectorProcess {
    private var process: Process?
    private let binaryURL: URL
    private let statusPath: String
    private let claudeHooksEnabled: Bool

    init(binaryURL: URL, statusPath: String, claudeHooksEnabled: Bool) {
        self.binaryURL = binaryURL
        self.statusPath = statusPath
        self.claudeHooksEnabled = claudeHooksEnabled
    }

    func start() {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = binaryURL
        proc.environment = ProcessInfo.processInfo.environment.merging(
            [
                "AGENT_TRAFFIC_LIGHTS_STATUS_PATH": statusPath,
                "AGENT_TRAFFIC_LIGHTS_PARENT_PID": "\(ProcessInfo.processInfo.processIdentifier)",
                "AGENT_TRAFFIC_LIGHTS_CLAUDE_HOOKS_ENABLED": claudeHooksEnabled ? "1" : "0"
            ],
            uniquingKeysWith: { _, new in new }
        )
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.start()
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            NSLog("collector failed to launch: \(error)")
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }
}
