import AgentTrafficLightsCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let store: StatusStore
    private let settings: AppSettings
    private let openAction = OpenCodexAction()
    private var panel: NSPanel?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []

    init(store: StatusStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.menuBarLength(for: settings.orientation))
        super.init()

        configureStatusItem()
        observePanelContentChanges()
        updateIcon()
    }

    func updateIcon() {
        statusItem.length = Self.menuBarLength(for: settings.orientation)
        statusItem.button?.image = TrafficLightIconRenderer.image(
            status: store.aggregateStatus,
            orientation: settings.orientation
        )
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.toolTip = "Agents: \(store.aggregateStatus.displayName)"
    }

    private static func menuBarLength(for orientation: TrafficLightOrientation) -> CGFloat {
        switch orientation {
        case .vertical:
            return NSStatusItem.squareLength
        case .horizontal:
            return 30
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observePanelContentChanges() {
        Publishers.CombineLatest4(
            store.$aggregateStatus,
            store.$visibleSessions,
            store.$lastUpdated,
            store.$message
        )
        .dropFirst()
        .sink { [weak self] _ in
            self?.refreshPanelContent()
        }
        .store(in: &cancellables)

        settings.$claudeCodeStatusMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshPanelContent()
            }
            .store(in: &cancellables)

        settings.$orientation
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshPanelContent()
            }
            .store(in: &cancellables)
    }

    private var panelView: StatusPanelView {
        StatusPanelView(
            store: store,
            settings: settings,
            width: preferredPanelWidth(),
            openSession: { [weak self] session in
                self?.closePanel()
                self?.openAction.open(session)
            },
            showClaudeCodeSettings: { [weak self] in
                self?.closePanel()
                self?.showSettings(selectedTab: .claudeCode)
            },
            showOnboarding: { [weak self] in
                self?.closePanel()
                self?.showOnboarding()
            },
            showSettings: { [weak self] in
                self?.closePanel()
                self?.showSettings()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    }

    private func refreshPanelContent() {
        if let controller = panel?.contentViewController as? NSHostingController<StatusPanelView> {
            controller.rootView = panelView
        }
        refreshPanelSize()
    }

    private func refreshPanelSize() {
        guard let panel else { return }
        let size = currentPanelSize()
        var frame = panel.frame
        let oldMaxY = frame.maxY
        frame.size = size
        frame.origin.y = oldMaxY - size.height
        panel.setFrame(frame, display: true)
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else {
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        if let controller = panel.contentViewController as? NSHostingController<StatusPanelView> {
            controller.rootView = panelView
        }
        let size = currentPanelSize()
        panel.setContentSize(size)
        panel.setFrameOrigin(panelOrigin(size: size, relativeTo: button))
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let panel = StatusPanel(
            contentRect: NSRect(origin: .zero, size: currentPanelSize()),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: panelView)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func currentPanelSize() -> NSSize {
        let sessionCount = max(store.visibleSessions.count, 1)
        let height = min(max(CGFloat(118 + sessionCount * 58 + 150), 300), 580)
        return NSSize(width: preferredPanelWidth(), height: height)
    }

    private func panelOrigin(size: NSSize, relativeTo button: NSStatusBarButton) -> NSPoint {
        guard let window = button.window else {
            return .zero
        }

        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(buttonFrame)
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 6
        var x = screenFrame.midX - size.width / 2
        x = min(max(x, screen.minX + margin), screen.maxX - size.width - margin)
        let y = screenFrame.minY - size.height - 6
        return NSPoint(x: x, y: max(y, screen.minY + margin))
    }

    private func closePanel() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    static func claudeCodeModeLabel(settings: AppSettings) -> String {
        switch settings.claudeCodeStatusMode {
        case .automatic:
            return "Transcript"
        case .hooks:
            return ClaudeHookInstaller.isInstalled() ? "Hooks" : "Hooks missing"
        }
    }

    static func lastUpdatedText(_ lastUpdated: Date?) -> String {
        guard let lastUpdated else {
            return "No update yet"
        }

        return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }

    static func providerIconImage(provider: String) -> NSImage {
        ProviderIconRenderer.image(provider: provider, size: NSSize(width: 15, height: 15), tint: .secondaryLabelColor)
    }

    private func preferredPanelWidth() -> CGFloat {
        let minimumWidth: CGFloat = 318
        let maximumWidth: CGFloat = 420
        var width = textWidth("Agents are \(store.aggregateStatus.displayName.lowercased())", size: 14, weight: .semibold)
            + textWidth(Self.lastUpdatedText(store.lastUpdated), size: 12, weight: .medium)
            + 92

        let claudeModeWidth = textWidth("Claude Code mode", size: 13, weight: .medium)
            + textWidth(Self.claudeCodeModeLabel(settings: settings), size: 11, weight: .medium)
            + 112
        width = max(width, claudeModeWidth)

        for session in store.visibleSessions {
            let textColumnWidth = max(
                textWidth(session.projectName, size: 13, weight: .semibold),
                textWidth(session.detail ?? session.status.displayName, size: 12, weight: .regular)
            )
            let badgeWidth = textWidth(session.status.displayName, size: 11, weight: .medium) + 44
            width = max(width, textColumnWidth + badgeWidth + 108)
        }

        return min(max(ceil(width), minimumWidth), maximumWidth)
    }

    private func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    func showOnboardingIfNeeded() {
        guard !settings.hasCompletedOnboarding else {
            return
        }

        showOnboarding()
    }

    private func showOnboarding() {
        if onboardingWindowController == nil {
            let controller = NSHostingController(rootView: OnboardingView(
                settings: settings,
                hookBinaryURL: claudeHookBinaryURL,
                onFinish: { [weak self] in
                    self?.onboardingWindowController?.close()
                }
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "Getting Started"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.contentMinSize = NSSize(width: 640, height: 460)
            window.setContentSize(NSSize(width: 640, height: 460))
            window.center()
            onboardingWindowController = NSWindowController(window: window)
        } else if let controller = onboardingWindowController?.contentViewController as? NSHostingController<OnboardingView> {
            controller.rootView = OnboardingView(
                settings: settings,
                hookBinaryURL: claudeHookBinaryURL,
                onFinish: { [weak self] in
                    self?.onboardingWindowController?.close()
                }
            )
        }

        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings(selectedTab: SettingsTab = .general) {
        if settingsWindowController == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings, selectedTab: selectedTab))
            let window = NSWindow(contentViewController: controller)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.contentMinSize = NSSize(width: 720, height: 500)
            window.setContentSize(NSSize(width: 780, height: 520))
            window.center()
            settingsWindowController = NSWindowController(window: window)
        } else if let controller = settingsWindowController?.contentViewController as? NSHostingController<SettingsView> {
            controller.rootView = SettingsView(settings: settings, selectedTab: selectedTab)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var claudeHookBinaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/AgentClaudeHook")
    }
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct StatusPanelView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var settings: AppSettings
    let width: CGFloat
    let openSession: (AgentSession) -> Void
    let showClaudeCodeSettings: () -> Void
    let showOnboarding: () -> Void
    let showSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeaderRow(
                statusText: "Agents are \(store.aggregateStatus.displayName.lowercased())",
                updatedText: StatusBarController.lastUpdatedText(store.lastUpdated),
                icon: TrafficLightIconRenderer.image(status: store.aggregateStatus, orientation: settings.orientation)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.visibleSessions.isEmpty ? store.message : sessionCountText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                if !store.visibleSessions.isEmpty {
                    ForEach(store.visibleSessions, id: \.id) { session in
                        SessionPopoverRow(
                            session: session,
                            canOpen: OpenCodexAction().canOpen(session),
                            action: {
                                openSession(session)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 4) {
                ClaudeCodeModePopoverRow(
                    modeLabel: StatusBarController.claudeCodeModeLabel(settings: settings),
                    action: showClaudeCodeSettings
                )
                CommandPopoverRow(title: "Getting Started...", symbolName: "sparkles", action: showOnboarding)
                CommandPopoverRow(title: "Settings...", symbolName: "gearshape", action: showSettings)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)

            Divider()

            CommandPopoverRow(title: "Quit Agent Light", symbolName: "power", action: quit)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
        .frame(width: width)
        .background(MenuMaterialView())
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var sessionCountText: String {
        let count = store.visibleSessions.count
        return count == 1 ? "1 agent session" : "\(count) agent sessions"
    }
}

private struct MenuMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .menu
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct PopoverHeaderRow: View {
    let statusText: String
    let updatedText: String
    let icon: NSImage

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 18)

            Text(statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.58))
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(updatedText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }
}

private struct SessionPopoverRow: View {
    let session: AgentSession
    let canOpen: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            if canOpen {
                action()
            }
        }) {
            HStack(spacing: 11) {
                Image(nsImage: ProviderIconRenderer.image(provider: session.provider, size: NSSize(width: 20, height: 20)))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(session.detail ?? session.status.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                SessionStatusBadge(status: session.status)
            }
            .padding(.horizontal, 7)
            .frame(height: 50)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering && canOpen ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .opacity(canOpen ? 1 : 0.72)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ClaudeCodeModePopoverRow: View {
    let modeLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(nsImage: StatusBarController.providerIconImage(provider: "claude-code"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .frame(width: 26, height: 26)

                Text("Claude Code mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 14)

                Text(modeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.11))
                    )
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct CommandPopoverRow: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct SessionStatusBadge: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(status.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor.opacity(0.13))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(statusColor.opacity(0.24), lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch status {
        case .failed:
            return Color(red: 1.0, green: 0.231, blue: 0.188)
        case .needsInput:
            return Color(red: 1.0, green: 0.749, blue: 0.0)
        case .working:
            return Color(red: 0.0, green: 0.651, blue: 0.318)
        case .idle, .unknown:
            return .gray
        }
    }
}
