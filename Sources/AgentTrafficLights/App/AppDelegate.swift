import AppKit
import Combine
@preconcurrency import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let store = StatusStore()
    private let watcher = StatusFileWatcher()
    private let updateChecker = UpdateChecker()
    private var alertNotifier: SessionAlertNotifier?
    private var statusBarController: StatusBarController?
    private var collectorProcess: CollectorProcess?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController(store: store, settings: settings, updateChecker: updateChecker)
        let notifier = SessionAlertNotifier()
        statusBarController = controller
        alertNotifier = notifier

        startCollector()

        store.$aggregateStatus
            .sink { [weak controller] _ in
                // `@Published` fires in `willSet`, so the property still holds the OLD value here.
                // Defer to the next main-actor tick so `updateIcon()` reads the committed value and
                // the menu-bar icon stays in sync with the SwiftUI panel (which renders post-commit).
                Task { @MainActor in controller?.updateIcon() }
            }
            .store(in: &cancellables)

        store.$visibleSessions
            .sink { [weak self, weak store, weak notifier] sessions in
                Task { @MainActor in
                    let notificationsEnabled = self?.settings.notificationsEnabled == true
                    notifier?.update(
                        aggregate: store?.aggregateStatus ?? .unknown,
                        sessions: sessions,
                        notifyOnAttention: notificationsEnabled && self?.settings.notifyOnAttention == true,
                        notifyOnSessionCompletion: notificationsEnabled && self?.settings.notifyOnSessionCompletion == true,
                        notifyOnAllCompletion: notificationsEnabled && self?.settings.notifyOnCompletion == true
                    )
                }
            }
            .store(in: &cancellables)

        settings.$orientation
            .sink { [weak controller] _ in
                Task { @MainActor in controller?.updateIcon() }
            }
            .store(in: &cancellables)

        settings.$claudeCodeStatusMode
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.restartCollector() }
            }
            .store(in: &cancellables)

        settings.$statusFilePath
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.restartCollector() }
            }
            .store(in: &cancellables)

        updateChecker.$state
            .dropFirst()
            .sink { [weak self] state in
                Task { @MainActor in self?.handleUpdateState(state) }
            }
            .store(in: &cancellables)

        watcher.start(
            pathProvider: { [settings] in settings.statusFilePath },
            onTick: { [store] path in
                store.reload(from: path)
            }
        )

        Task { @MainActor in
            controller.showOnboardingIfNeeded()
        }

        Task { @MainActor in
            await updateChecker.checkIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        collectorProcess?.stop()
        watcher.stop()
    }

    private func startCollector() {
        let collectorURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/AgentStatusCollector")
        let collector = CollectorProcess(
            binaryURL: collectorURL,
            statusPath: settings.statusFilePath,
            claudeHooksEnabled: settings.claudeCodeStatusMode == .hooks
        )
        collector.start()
        collectorProcess = collector
    }

    private func restartCollector() {
        collectorProcess?.stop()
        startCollector()
    }

    private func handleUpdateState(_ state: UpdateCheckState) {
        guard settings.notificationsEnabled,
              case let .updateAvailable(update) = state,
              updateChecker.shouldNotifyUser(about: update) else {
            return
        }

        updateChecker.markUserNotified(about: update)

        let content = UNMutableNotificationContent()
        content.title = "Agent Light \(update.version) is available"
        content.body = "You are running \(update.currentVersion). Open Agent Light from the menu bar to view the release."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "agent-light-update-\(update.version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
