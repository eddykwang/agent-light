import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    let hookBinaryURL: URL
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var selectedOrientation: TrafficLightOrientation
    @State private var selectedClaudeMode: ClaudeCodeStatusMode
    @State private var hooksInstalled: Bool
    @State private var message: String?
    @State private var showsHookInstallPanel = false

    init(settings: AppSettings, hookBinaryURL: URL, onFinish: @escaping () -> Void) {
        self.settings = settings
        self.hookBinaryURL = hookBinaryURL
        self.onFinish = onFinish
        _selectedOrientation = State(initialValue: settings.orientation)
        _selectedClaudeMode = State(initialValue: settings.claudeCodeStatusMode)
        _hooksInstalled = State(initialValue: ClaudeHookInstaller.isInstalled())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            progress

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        switch step {
                        case .welcome:
                            welcomePage
                        case .signal:
                            signalPage
                        case .claudeCode:
                            claudeCodePage
                        case .complete:
                            completePage
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(26)
        .frame(width: 680, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedOrientation = settings.orientation
            selectedClaudeMode = settings.claudeCodeStatusMode
            reconcileHooksMode()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: TrafficLightIconRenderer.image(status: .working, orientation: selectedOrientation))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 46, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Agent Light")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                Text(step.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.18))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Agent Light")
                    .font(.system(size: 20, weight: .semibold))
                Text("Watch active coding agents from the menu bar without switching windows.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                PlatformCard(
                    systemImage: "terminal",
                    title: "Codex",
                    subtitle: "Supported now",
                    message: "Reads local status output and presents a compact traffic-light signal."
                )

                PlatformCard(
                    systemImage: "curlybraces",
                    title: "Claude Code",
                    subtitle: "Supported now",
                    message: "Uses transcript detection by default, with optional hooks for more precise events."
                )

                PlatformCard(
                    systemImage: "plus",
                    title: "More Coming",
                    subtitle: "Planned",
                    message: "Additional local agent integrations will fit into the same menu-bar signal."
                )
            }

            PrivacyNote()
        }
    }

    private var signalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose the menu-bar indicator")
                    .font(.system(size: 20, weight: .semibold))
                Text("Pick the layout that reads best in your menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                OrientationCard(
                    title: "Horizontal",
                    message: "A wider signal that mirrors a standard traffic light.",
                    orientation: .horizontal,
                    isSelected: selectedOrientation == .horizontal
                ) {
                    selectOrientation(.horizontal)
                }

                OrientationCard(
                    title: "Vertical",
                    message: "A compact stack that works well beside dense menu-bar items.",
                    orientation: .vertical,
                    isSelected: selectedOrientation == .vertical
                ) {
                    selectOrientation(.vertical)
                }
            }
        }
    }

    private var claudeCodePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Claude Code mode")
                    .font(.system(size: 20, weight: .semibold))
                Text("This step is only for Claude Code users. If you do not use Claude Code, choose Transcript and finish setup.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                ClaudeModeCard(
                    title: "Hooks",
                    subtitle: hooksInstalled ? "Claude Code, installed" : "Claude Code users",
                    message: "Recommended if you use Claude Code. Adds lifecycle events for working, input, permission, and completion states.",
                    badge: "Recommended",
                    isSelected: selectedClaudeMode == .hooks || showsHookInstallPanel
                ) {
                    chooseHooks()
                }

                ClaudeModeCard(
                    title: "Transcript",
                    subtitle: "No setup",
                    message: "Use this if you do not use Claude Code, or if you want to finish without installing hooks.",
                    badge: nil,
                    isSelected: selectedClaudeMode == .automatic && !showsHookInstallPanel
                ) {
                    applyClaudeChoice(.declined)
                }
            }

            if showsHookInstallPanel {
                HookInstallPanel(
                    hookBinaryPath: hookBinaryURL.path,
                    onInstall: installHooks,
                    onUseTranscript: {
                        applyClaudeChoice(.declined)
                    }
                )
            }
        }
    }

    private var completePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup complete")
                    .font(.system(size: 20, weight: .semibold))
                Text("Agent Light is ready in your menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                CompletionReminder(
                    systemImage: "arrow.clockwise",
                    title: "Start a new agent session",
                    message: "Status changes are most reliable for sessions started after setup."
                )

                CompletionReminder(
                    systemImage: selectedClaudeMode == .hooks ? "link.badge.plus" : "doc.text.magnifyingglass",
                    title: selectedClaudeMode == .hooks ? "Claude Code hooks are ready" : "Transcript mode is selected",
                    message: selectedClaudeMode == .hooks
                        ? "Open a new Claude Code session so the installed hooks can send lifecycle events."
                        : "You can install Claude Code hooks later from Settings if you want more precise Claude Code events."
                )

                CompletionReminder(
                    systemImage: "menubar.rectangle",
                    title: "You can reopen this anytime",
                    message: "Use Getting Started from the Agent Light menu to review these choices."
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Back") {
                if let previous = step.previous {
                    step = previous
                }
            }
            .disabled(step.previous == nil)

            Spacer()

            if let next = step.next {
                Button(step == .claudeCode ? "Next" : "Continue") {
                    if step == .claudeCode {
                        reconcileHooksMode()
                    }
                    step = next
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            } else {
                Button("Done") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var canContinue: Bool {
        step != .claudeCode || !showsHookInstallPanel
    }

    private func selectOrientation(_ orientation: TrafficLightOrientation) {
        selectedOrientation = orientation
        settings.orientation = orientation
    }

    private func chooseHooks() {
        let installed = ClaudeHookInstaller.isInstalled()
        hooksInstalled = installed

        if installed {
            selectedClaudeMode = .hooks
            settings.claudeCodeStatusMode = .hooks
            showsHookInstallPanel = false
            message = "Hooks are installed. Start a new Claude Code session for the most reliable status events."
        } else {
            selectedClaudeMode = .automatic
            settings.claudeCodeStatusMode = .automatic
            showsHookInstallPanel = true
            message = "Hooks are only needed for Claude Code users. Install hooks to continue with Hooks mode, or choose Transcript to finish setup."
        }
    }

    private func installHooks() {
        do {
            try ClaudeHookInstaller.install(hookBinaryURL: hookBinaryURL)
            applyClaudeChoice(.installed)
        } catch {
            applyClaudeChoice(.failed(error.localizedDescription))
        }
    }

    private func applyClaudeChoice(_ outcome: ClaudeCodeHookChoiceOutcome) {
        let resolution = ClaudeCodeHookChoiceResolution.resolve(outcome)
        hooksInstalled = resolution.hooksInstalled || ClaudeHookInstaller.isInstalled()
        selectedClaudeMode = resolution.mode
        settings.claudeCodeStatusMode = resolution.mode
        message = resolution.message

        switch outcome {
        case .installed, .declined:
            showsHookInstallPanel = false
        case .failed:
            showsHookInstallPanel = true
        }
    }

    private func reconcileHooksMode() {
        hooksInstalled = ClaudeHookInstaller.isInstalled()

        guard selectedClaudeMode == .hooks, !hooksInstalled else {
            return
        }

        selectedClaudeMode = .automatic
        settings.claudeCodeStatusMode = .automatic
        showsHookInstallPanel = false
        message = "Transcript mode selected until Claude Code hooks are installed."
    }

    private func finish() {
        reconcileHooksMode()
        settings.orientation = selectedOrientation
        settings.claudeCodeStatusMode = selectedClaudeMode
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}

private struct PlatformCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct PrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("Local metadata only")
                    .font(.system(size: 13, weight: .semibold))
                Text("Agent Light stores status metadata only. It does not store prompts, tool inputs, or model responses.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct CompletionReminder: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.50))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct OrientationCard: View {
    let title: String
    let message: String
    let orientation: TrafficLightOrientation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 10)

                    SelectionMark(isSelected: isSelected)
                }

                Spacer(minLength: 0)

                TrafficLightPreview(orientation: orientation)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var cardFill: some ShapeStyle {
        isSelected
            ? Color.accentColor.opacity(0.10)
            : Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }

    private var cardStroke: Color {
        isSelected ? Color.accentColor.opacity(0.40) : Color.primary.opacity(0.06)
    }
}

private struct ClaudeModeCard: View {
    let title: String
    let subtitle: String
    let message: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            if let badge {
                                Text(badge)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.12))
                                    )
                            }
                        }

                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    SelectionMark(isSelected: isSelected)
                }

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var cardFill: some ShapeStyle {
        isSelected
            ? Color.accentColor.opacity(0.10)
            : Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }

    private var cardStroke: Color {
        isSelected ? Color.accentColor.opacity(0.40) : Color.primary.opacity(0.06)
    }
}

private struct HookInstallPanel: View {
    let hookBinaryPath: String
    let onInstall: () -> Void
    let onUseTranscript: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text("For Claude Code users: install hooks")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Agent Light will add local Claude Code hook entries to ~/.claude/settings.json. If you do not use Claude Code, choose Transcript instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Hook command")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(hookBinaryPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
            )

            HStack(spacing: 10) {
                Button("Use Transcript", action: onUseTranscript)

                Spacer()

                Button {
                    onInstall()
                } label: {
                    Label("Install Hooks", systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        }
    }
}

private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 18, height: 18)
    }
}

private struct TrafficLightPreview: View {
    let orientation: TrafficLightOrientation

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))

            Image(nsImage: TrafficLightIconRenderer.image(status: .working, orientation: orientation))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(14)
        }
        .frame(width: 96, height: 70)
    }
}
