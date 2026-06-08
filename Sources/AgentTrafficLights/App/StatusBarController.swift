import AgentTrafficLightsCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let store: StatusStore
    private let settings: AppSettings
    private let openAction = OpenCodexAction()
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var isMenuOpen = false
    private var menuRefreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(store: StatusStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.menuBarLength(for: settings.orientation))
        super.init()

        configureStatusItem()
        observeMenuContentChanges()
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
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        menuRefreshTask?.cancel()
        menuRefreshTask = nil
    }

    private func observeMenuContentChanges() {
        Publishers.CombineLatest4(
            store.$aggregateStatus,
            store.$visibleSessions,
            store.$lastUpdated,
            store.$message
        )
        .dropFirst()
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.scheduleMenuRefreshIfOpen()
            }
        }
        .store(in: &cancellables)

        settings.$claudeCodeStatusMode
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleMenuRefreshIfOpen()
                }
            }
            .store(in: &cancellables)

        settings.$orientation
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleMenuRefreshIfOpen()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleMenuRefreshIfOpen() {
        guard isMenuOpen else {
            return
        }

        menuRefreshTask?.cancel()
        menuRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled, self.isMenuOpen else {
                return
            }

            self.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let contentWidth = preferredMenuWidth()

        menu.removeAllItems()
        menu.addItem(headerItem(width: contentWidth))
        menu.addItem(sessionCountItem())

        if !store.visibleSessions.isEmpty {
            menu.addItem(.separator())
            store.visibleSessions.forEach { session in
                menu.addItem(sessionItem(for: session, width: contentWidth))
            }
        }

        menu.addItem(.separator())
        menu.addItem(claudeCodeModeItem(width: contentWidth))

        let onboardingItem = NSMenuItem(title: "Getting Started...", action: #selector(showOnboardingFromMenu), keyEquivalent: "")
        onboardingItem.target = self
        onboardingItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Getting Started")
        menu.addItem(onboardingItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Agent Light", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
    }

    private func headerItem(width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let row = MenuHeaderRowView(
            statusText: "Agents are \(store.aggregateStatus.displayName.lowercased())",
            updatedText: lastUpdatedText,
            icon: TrafficLightIconRenderer.image(status: store.aggregateStatus, orientation: settings.orientation),
            width: width
        )
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 36)
        item.view = hostingView
        return item
    }

    private func sessionCountItem() -> NSMenuItem {
        let count = store.visibleSessions.count
        let title = count == 1 ? "1 agent session" : "\(count) agent sessions"
        let item = NSMenuItem(title: count > 0 ? title : store.message, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func sessionItem(for session: AgentSession, width: CGFloat) -> NSMenuItem {
        let detail = session.detail ?? session.status.displayName
        let canOpen = openAction.canOpen(session)
        let item = NSMenuItem()
        let row = SessionMenuRowView(
            projectName: session.projectName,
            detail: detail,
            providerIcon: ProviderIconRenderer.image(provider: session.provider, size: NSSize(width: 20, height: 20)),
            status: session.status,
            canOpen: canOpen,
            width: width
        ) { [weak self] in
            guard let self, canOpen else {
                return
            }

            self.menu.cancelTracking()
            self.openAction.open(session)
        }
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 54)
        item.view = hostingView
        return item
    }

    private func claudeCodeModeItem(width: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let row = ClaudeCodeModeRowView(
            modeLabel: claudeCodeModeLabel,
            providerIcon: providerIconImage(provider: "claude-code"),
            width: width
        ) { [weak self] in
            self?.menu.cancelTracking()
            self?.showSettings(selectedTab: .claudeCode)
        }
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        item.view = hostingView
        return item
    }

    private var claudeCodeModeLabel: String {
        switch settings.claudeCodeStatusMode {
        case .automatic:
            return "Transcript"
        case .hooks:
            return ClaudeHookInstaller.isInstalled() ? "Hooks" : "Hooks missing"
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = store.lastUpdated else {
            return "No update yet"
        }

        return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }

    private func providerIconImage(provider: String) -> NSImage {
        ProviderIconRenderer.image(provider: provider, size: NSSize(width: 15, height: 15), tint: .secondaryLabelColor)
    }

    private func preferredMenuWidth() -> CGFloat {
        let minimumWidth: CGFloat = 340
        let maximumWidth: CGFloat = 460
        var width: CGFloat = textWidth("Agents are \(store.aggregateStatus.displayName.lowercased())", size: 13, weight: .semibold)
            + textWidth(lastUpdatedText, size: 12, weight: .medium)
            + 94

        width = max(
            width,
            textWidth("Claude Code mode", size: 13, weight: .medium)
                + textWidth(claudeCodeModeLabel, size: 11, weight: .medium)
                + 116
        )

        for session in store.visibleSessions {
            let detail = session.detail ?? session.status.displayName
            let textColumnWidth = max(
                textWidth(session.projectName, size: 13, weight: .semibold),
                textWidth(detail, size: 12, weight: .regular)
            )
            let badgeWidth = textWidth(session.status.displayName, size: 11, weight: .medium) + 44
            width = max(width, textColumnWidth + badgeWidth + 93)
        }

        return min(max(ceil(width), minimumWidth), maximumWidth)
    }

    private func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    func showOnboardingIfNeeded() {
        guard !settings.hasCompletedOnboarding else {
            return
        }

        showOnboarding()
    }

    @objc private func showOnboardingFromMenu() {
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

    @objc private func showClaudeCodeSettingsFromMenu() {
        showSettings(selectedTab: .claudeCode)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
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

private struct MenuHeaderRowView: View {
    let statusText: String
    let updatedText: String
    let icon: NSImage
    let width: CGFloat

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 18)

            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.44))
                .lineLimit(1)

            Spacer(minLength: 14)

            Text(updatedText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 36)
    }
}

private struct SessionMenuRowView: View {
    let projectName: String
    let detail: String
    let providerIcon: NSImage
    let status: AgentStatus
    let canOpen: Bool
    let width: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            if canOpen {
                action()
            }
        }) {
            HStack(spacing: 11) {
                Image(nsImage: providerIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                SessionStatusBadge(status: status)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: 54)
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

private struct ClaudeCodeModeRowView: View {
    let modeLabel: String
    let providerIcon: NSImage
    let width: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(nsImage: providerIcon)
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
            .padding(.horizontal, 10)
            .frame(width: width, height: 40)
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
