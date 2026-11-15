import SwiftUI

struct CodexHooksView: View {
    @State private var status: CodexHookInstallStatus = .notInstalled
    @State private var message: String?
    private var binary: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/AgentCodexHook") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex hooks (optional)").font(.headline)
            Text("Without hooks, Agent Light reads local rollouts. Hooks add permission and turn lifecycle signals using status metadata only. Use Codex 0.169 or later; upgrade older CLI versions sharing this Codex home before installing hooks.")
                .font(.callout).foregroundStyle(.secondary)
            Text(statusText).font(.callout)
            HStack {
                Button(status == .needsReinstall ? "Repair Hooks" : "Install Hooks") {
                    do {
                        try CodexHookInstaller.install(hookBinaryURL: binary)
                        message = "Configuration saved. Review and trust Agent Light hooks in Codex before they can run."
                    } catch { message = error.localizedDescription }
                    refresh()
                }
                .disabled(status == .configured || status == .invalidConfiguration)
                Button("Remove Hooks") {
                    do { try CodexHookInstaller.remove(); message = "Hooks removed. Rollout detection remains available." }
                    catch { message = error.localizedDescription }
                    refresh()
                }
                .disabled(status != .configured && status != .needsReinstall)
            }
            .buttonStyle(.bordered)
            Text("In the Codex app: Settings → Hooks. In Codex CLI: /hooks. Review new or changed hooks, including after moving Agent Light. Configuration presence does not prove trust or CLI support.")
                .font(.callout).foregroundStyle(.secondary)
            Text(CodexHookInstaller.defaultHooksURL.path).font(.caption).textSelection(.enabled)
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
        .onAppear(perform: refresh)
    }

    private var statusText: String {
        switch status {
        case .notInstalled: return "Hooks are not configured. Rollout detection is active."
        case .configured: return "Hooks configured. Review trust in Codex; trust cannot be verified here."
        case .needsReinstall: return "Hook configuration needs repair for this app path."
        case .invalidConfiguration: return "Existing hooks.json is invalid. Fix it in Codex before installing; Agent Light has not overwritten it."
        }
    }

    private func refresh() { status = CodexHookInstaller.status(hookBinaryURL: binary) }
}
