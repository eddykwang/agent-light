import Foundation
import AgentTrafficLightsCore
import Darwin

let defaultPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.agent-traffic-lights/status.json"
let statusPath = ProcessInfo.processInfo.environment["AGENT_TRAFFIC_LIGHTS_STATUS_PATH"] ?? defaultPath
let interval = ProcessInfo.processInfo.environment["AGENT_TRAFFIC_LIGHTS_INTERVAL"]
    .flatMap(TimeInterval.init) ?? 1.0
let parentPID = ProcessInfo.processInfo.environment["AGENT_TRAFFIC_LIGHTS_PARENT_PID"]
    .flatMap(Int32.init)
let claudeHooksEnabled = ProcessInfo.processInfo.environment["AGENT_TRAFFIC_LIGHTS_CLAUDE_HOOKS_ENABLED"] == "1"

var sources: [any SessionSource] = []
if claudeHooksEnabled {
    sources.append(ClaudeCodeHookSource())
}
sources.append(CopilotHookSource())
sources.append(ClaudeCodeTranscriptSource())
sources.append(CodexRolloutSource())

let runner = CollectorRunner(
    sources: sources,
    liveness: LsofLivenessFilter(),
    writer: StatusFileWriter(),
    statusPath: statusPath
)

func parentIsAlive() -> Bool {
    guard let parentPID, parentPID > 1 else {
        return true
    }
    return kill(parentPID, 0) == 0
}

while parentIsAlive() {
    autoreleasepool {
        do { try runner.runOnce() } catch {
            FileHandle.standardError.write(Data("collector error: \(error)\n".utf8))
        }
    }
    Thread.sleep(forTimeInterval: interval)
}
