import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

struct SettingsView: View {
    private static let githubURL = URL(string: "https://github.com/eddywang/agent-light")!

    @ObservedObject var settings: AppSettings
    @State private var selectedTab: SettingsTab
    @State private var launchAtLoginError: String?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?
    @State private var notificationTestMessage: String?
    @State private var claudeHooksInstalled = false
    @State private var claudeHookMessage: String?
    @FocusState private var isPathFieldFocused: Bool

    init(settings: AppSettings, selectedTab: SettingsTab = .general) {
        self.settings = settings
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            contentPane
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.smooth(duration: 0.18), value: settings.orientation)
        .animation(.smooth(duration: 0.18), value: settings.claudeCodeStatusMode)
        .animation(.smooth(duration: 0.16), value: selectedTab)
        .onAppear {
            refreshLaunchAtLoginStatus()
            refreshNotificationAuthorizationStatus()
            refreshClaudeHookStatus()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            appIdentity

            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .frame(width: 218)
        .background(.bar)
    }

    private var appIdentity: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.grid.3x3")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Light")
                    .font(.system(size: 14, weight: .semibold))
                Text("Local agent monitor")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private var contentPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(selectedTab.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                    .textSelection(.disabled)

                tabContent
                    .id(selectedTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalPane
        case .claudeCode:
            claudeCodePane
        case .notifications:
            notificationsPane
        case .advanced:
            advancedPane
        case .about:
            aboutPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Appearance") {
                SettingsRow(
                    title: "Traffic light layout",
                    subtitle: settings.orientation == .vertical ? "Vertical menu bar signal" : "Horizontal menu bar signal",
                    systemImage: "menubar.rectangle"
                ) {
                    HStack(spacing: 10) {
                        TrafficLightPreview(orientation: settings.orientation)

                        Picker("Traffic light layout", selection: $settings.orientation) {
                            ForEach(TrafficLightOrientation.allCases) { orientation in
                                Text(orientation.displayName).tag(orientation)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 178)
                    }
                }
            }

            SettingsGroup(title: "Startup") {
                SettingsToggleRow(
                    title: "Launch at login",
                    subtitle: "Start Agent Light automatically when you sign in to this Mac.",
                    systemImage: "power",
                    isOn: launchAtLoginBinding
                )

                if let launchAtLoginError {
                    SettingsDivider()

                    Text(launchAtLoginError)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var claudeCodePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Mode comparison") {
                ClaudeModeComparisonTable()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            SettingsGroup(title: "Claude Code hooks") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hooks ask Claude Code to send lifecycle status events to Agent Light, such as working, permission needed, input needed, and completed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Agent Light only stores status metadata. It does not access or store your prompts, tool inputs, or model responses.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                SettingsDivider()

                SettingsRow(
                    title: "Status detection",
                    subtitle: claudeDetectionSubtitle,
                    systemImage: "claude.code.brand"
                ) {
                    Picker("Claude Code status detection", selection: claudeModeBinding) {
                        ForEach(ClaudeCodeStatusMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }

                SettingsDivider()

                SettingsRow(
                    title: claudeHooksInstalled ? "Hooks installed" : "Hooks not installed",
                    subtitle: claudeHooksInstalled
                        ? "Agent Light hook entries are present in Claude Code settings."
                        : "Install hook entries before using Hooks mode for precise Claude Code status.",
                    systemImage: claudeHooksInstalled ? "checkmark.seal" : "link.badge.plus"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            installClaudeHooks()
                        } label: {
                            Label("Install", systemImage: "plus")
                        }
                        .disabled(claudeHooksInstalled)

                        Button {
                            removeClaudeHooks()
                        } label: {
                            Label("Remove", systemImage: "minus")
                        }
                        .disabled(!claudeHooksInstalled)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let claudeHookMessage {
                    SettingsDivider()

                    Text(claudeHookMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var advancedPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsInfoBox(
                title: "Most users should keep the default",
                message: "Agent Light reads a local JSON status file written by its collector. Change this only if you are debugging, testing another collector, or intentionally using a custom compatible status file."
            )

            SettingsGroup(title: "Status source") {
                SettingsRow(
                    title: "Status file",
                    subtitle: isUsingDefaultStatusFile ? "Default local status file." : "Custom local status file.",
                    systemImage: "doc.text.magnifyingglass"
                ) {
                    TextField("Status source path", text: $settings.statusFilePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($isPathFieldFocused)
                        .frame(width: 290)
                }

                SettingsDivider()

                SettingsRow(
                    title: "File actions",
                    subtitle: "Reveal the current file or restore the default path.",
                    systemImage: "folder"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            chooseStatusFile()
                        } label: {
                            Image(systemName: "folder")
                                .frame(width: 18)
                        }
                        .help("Choose status file")
                        .accessibilityLabel("Choose status file")

                        Button {
                            revealStatusFile()
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .frame(width: 18)
                        }
                        .help("Reveal status file")
                        .accessibilityLabel("Reveal status file")

                        Button {
                            settings.statusFilePath = AppSettings.defaultStatusFilePath
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 18)
                        }
                        .disabled(isUsingDefaultStatusFile)
                        .help("Use default status file")
                        .accessibilityLabel("Use default status file")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var notificationsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Agent Light notifications") {
                SettingsToggleRow(
                    title: "Allow notifications",
                    subtitle: "Turn off all Agent Light notifications.",
                    systemImage: "bell.badge",
                    isOn: $settings.notificationsEnabled
                )

                SettingsDivider()

                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Needs attention",
                        subtitle: "Notify when an agent needs input or fails.",
                        systemImage: "hand.raised",
                        isOn: $settings.notifyOnAttention
                    )

                    SettingsDivider()

                    SettingsRow(
                        title: "Completion",
                        subtitle: settings.completionNotificationMode.description,
                        systemImage: "checkmark.circle"
                    ) {
                        Picker("Completion notifications", selection: $settings.completionNotificationMode) {
                            ForEach(CompletionNotificationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 232)
                    }
                }
                .disabled(!settings.notificationsEnabled)
                .opacity(settings.notificationsEnabled ? 1 : 0.55)
            }

            SettingsGroup(title: "macOS permission") {
                SettingsRow(
                    title: "System permission",
                    subtitle: notificationPermissionSubtitle,
                    systemImage: notificationPermissionIcon
                ) {
                    Button {
                        sendTestNotification()
                    } label: {
                        Label("Send Test", systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Send a test notification")
                    .accessibilityLabel("Send a test notification")
                }

                if let notificationTestMessage {
                    SettingsDivider()

                    Text(notificationTestMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Application") {
                HStack(alignment: .center, spacing: 18) {
                    Image(nsImage: TrafficLightIconRenderer.image(status: .working, orientation: .horizontal))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 66, height: 48)
                        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Agent Light")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Version \(appVersion)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("A quiet menu bar app that watches local Codex and Claude Code sessions and tells you when work is running, done, blocked, or failed.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(20)
            }

            SettingsGroup(title: "Open source") {
                SettingsRow(
                    title: "GitHub",
                    subtitle: Self.githubURL.absoluteString,
                    systemImage: "chevron.left.forwardslash.chevron.right"
                ) {
                    Button {
                        NSWorkspace.shared.open(Self.githubURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                settings.launchAtLogin
            },
            set: { newValue in
                do {
                    try LaunchAtLoginController.setEnabled(newValue)
                    settings.launchAtLogin = newValue
                    refreshLaunchAtLoginStatus()
                } catch {
                    settings.launchAtLogin = false
                    launchAtLoginError = "macOS could not update the login item. Move the app to Applications and try again."
                }
            }
        )
    }

    private func refreshLaunchAtLoginStatus() {
        switch LaunchAtLoginController.state {
        case .enabled:
            if !settings.launchAtLogin {
                settings.launchAtLogin = true
            }
            launchAtLoginError = nil
        case .requiresApproval:
            launchAtLoginError = settings.launchAtLogin
                ? "macOS is waiting for approval in System Settings > General > Login Items."
                : nil
        case .notRegistered:
            launchAtLoginError = settings.launchAtLogin
                ? "Launch at login is not registered yet. Turn it off and on again to retry."
                : nil
        case .notFound:
            launchAtLoginError = settings.launchAtLogin
                ? "macOS cannot find this app as a login item. Move Agent Light to Applications and turn this on again."
                : nil
        case .unknown:
            launchAtLoginError = settings.launchAtLogin
                ? "macOS reported an unknown login item state."
                : nil
        }
    }

    private var claudeDetectionSubtitle: String {
        if settings.claudeCodeStatusMode == .hooks, !claudeHooksInstalled {
            return "Hooks mode is selected, but hook entries are not installed yet."
        }
        return settings.claudeCodeStatusMode.description
    }

    private var notificationPermissionSubtitle: String {
        switch notificationAuthorizationStatus {
        case .authorized:
            return "Allowed by macOS. Agent Light can show banners."
        case .denied:
            return "Blocked by macOS. Enable Agent Light in System Settings > Notifications."
        case .notDetermined:
            return "Not registered yet. Send a test notification to ask macOS for permission."
        case .provisional:
            return "Allowed quietly by macOS."
        case .ephemeral:
            return "Temporarily allowed by macOS."
        case .none:
            return "Checking macOS notification permission..."
        @unknown default:
            return "macOS returned an unknown permission state."
        }
    }

    private var notificationPermissionIcon: String {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell"
        case .denied:
            return "bell.slash"
        case .notDetermined, .none:
            return "questionmark.circle"
        @unknown default:
            return "exclamationmark.triangle"
        }
    }

    private func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// Selecting "Hooks" auto-installs the hook if it isn't present yet, so the picker can never
    /// leave the app in hooks mode without the hook actually wired into Claude Code settings.
    /// Selecting "Transcript" only switches the mode; removal stays an explicit action.
    private var claudeModeBinding: Binding<ClaudeCodeStatusMode> {
        Binding(
            get: { settings.claudeCodeStatusMode },
            set: { newMode in
                switch newMode {
                case .hooks:
                    if claudeHooksInstalled {
                        settings.claudeCodeStatusMode = .hooks
                    } else {
                        installClaudeHooks()
                    }
                case .automatic:
                    settings.claudeCodeStatusMode = .automatic
                }
            }
        )
    }

    private func refreshClaudeHookStatus() {
        claudeHooksInstalled = ClaudeHookInstaller.isInstalled()
    }

    private func installClaudeHooks() {
        do {
            try ClaudeHookInstaller.install(hookBinaryURL: claudeHookBinaryURL)
            settings.claudeCodeStatusMode = .hooks
            claudeHooksInstalled = true
            claudeHookMessage = "Claude Code hooks are enabled. New Claude sessions will report precise permission, input, and completion events to Agent Light."
        } catch {
            settings.claudeCodeStatusMode = .automatic
            refreshClaudeHookStatus()
            claudeHookMessage = "Agent Light could not update ~/.claude/settings.json: \(error.localizedDescription)"
        }
    }

    private func removeClaudeHooks() {
        do {
            try ClaudeHookInstaller.remove()
            settings.claudeCodeStatusMode = .automatic
            claudeHooksInstalled = false
            claudeHookMessage = "Claude Code hooks were removed. Agent Light is using default transcript detection."
        } catch {
            refreshClaudeHookStatus()
            claudeHookMessage = "Agent Light could not update ~/.claude/settings.json: \(error.localizedDescription)"
        }
    }

    private func sendTestNotification() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Task { @MainActor in
                    notificationTestMessage = "macOS could not request notification permission: \(error.localizedDescription)"
                    refreshNotificationAuthorizationStatus()
                }
                return
            }

            guard granted else {
                Task { @MainActor in
                    notificationTestMessage = "macOS denied notification permission. Open System Settings > Notifications and allow Agent Light."
                    refreshNotificationAuthorizationStatus()
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Agent Light test notification"
            content.body = "Notifications are working on this Mac."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "agent-light-test-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                Task { @MainActor in
                    if let error {
                        notificationTestMessage = "macOS could not send the test notification: \(error.localizedDescription)"
                    } else {
                        notificationTestMessage = "Test notification sent. If no banner appears, check Focus mode and System Settings > Notifications."
                    }
                    refreshNotificationAuthorizationStatus()
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return "0.1.1"
        }
    }

    private var claudeHookBinaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/AgentClaudeHook")
    }

    private var isUsingDefaultStatusFile: Bool {
        settings.statusFilePath == AppSettings.defaultStatusFilePath
    }

    private func chooseStatusFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(fileURLWithPath: settings.statusFilePath).deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            settings.statusFilePath = url.path
        }
    }

    private func revealStatusFile() {
        let url = URL(fileURLWithPath: settings.statusFilePath)
        let revealURL = FileManager.default.fileExists(atPath: url.path)
            ? url
            : url.deletingLastPathComponent()

        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case claudeCode
    case notifications
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .claudeCode:
            return "Claude Code"
        case .notifications:
            return "Notification"
        case .advanced:
            return "Advanced"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .claudeCode:
            return "claude.code.brand"
        case .notifications:
            return "bell"
        case .advanced:
            return "wrench.and.screwdriver"
        case .about:
            return "info.circle"
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MonochromeIcon(
                    systemImage: tab.systemImage,
                    size: 24,
                    imageSize: 15,
                    isSelected: isSelected
                )

                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 20)

            VStack(spacing: 0) {
                content
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: 570, alignment: .leading)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MonochromeIcon(systemImage: systemImage, size: 28, imageSize: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer(minLength: 18)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        ) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SettingsInfoBox: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .frame(maxWidth: 570, alignment: .leading)
    }
}

private struct ClaudeModeComparisonTable: View {
    private let rows: [ClaudeModeComparisonRow] = [
        .init(
            status: "Green: working",
            defaultValue: "Detects active turns from transcripts",
            hooksValue: "Detects active turns from lifecycle events"
        ),
        .init(
            status: "Yellow: needs input",
            defaultValue: "Best effort; may miss permission prompts",
            hooksValue: "More precise for permission and input"
        ),
        .init(
            status: "Red: failed",
            defaultValue: "Avoids many false alarms",
            hooksValue: "Can show explicit stop failures"
        ),
        .init(
            status: "Done: idle",
            defaultValue: "Inferred after transcript settles",
            hooksValue: "Reported when Claude finishes"
        ),
        .init(
            status: "Completion alerts",
            defaultValue: "Works, but timing can lag",
            hooksValue: "More timely"
        ),
        .init(
            status: "Privacy",
            defaultValue: "Local only",
            hooksValue: "Same; status metadata only"
        )
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                header("Status")
                header("Transcript")
                header("Hooks")
            }

            Divider()
                .gridCellColumns(3)

            ForEach(rows) { row in
                GridRow(alignment: .top) {
                    Text(row.status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    value(row.defaultValue)
                    value(row.hooksValue)
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ClaudeModeComparisonRow: Identifiable {
    let status: String
    let defaultValue: String
    let hooksValue: String

    var id: String { status }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 58)
    }
}

private struct MonochromeIcon: View {
    let systemImage: String
    let size: CGFloat
    let imageSize: CGFloat
    var isSelected = false

    var body: some View {
        Group {
            if systemImage == "claude.code.brand" {
                Image(nsImage: ProviderIconRenderer.image(
                    provider: "claude-code",
                    size: NSSize(width: imageSize + 2, height: imageSize + 2),
                    tint: iconTint
                ))
                    .frame(width: imageSize + 2, height: imageSize + 2)
            } else if systemImage == "codex.brand" {
                Image(nsImage: ProviderIconRenderer.image(
                    provider: "codex",
                    size: NSSize(width: imageSize + 2, height: imageSize + 2),
                    tint: iconTint
                ))
                    .frame(width: imageSize + 2, height: imageSize + 2)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: imageSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var iconTint: NSColor {
        isSelected ? .white : .secondaryLabelColor
    }
}

private struct TrafficLightPreview: View {
    let orientation: TrafficLightOrientation

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))

            Image(nsImage: TrafficLightIconRenderer.image(status: .working, orientation: orientation))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(width: 48, height: 38)
    }
}
