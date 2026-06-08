import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let store = StatusStore()
    private let watcher = StatusFileWatcher()
    private var alertNotifier: SessionAlertNotifier?
    private var statusBarController: StatusBarController?
    private var collectorProcess: CollectorProcess?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController(store: store, settings: settings)
        let notifier = SessionAlertNotifier()
        statusBarController = controller
        alertNotifier = notifier

        startCollector()

        store.$aggregateStatus
            .sink { [weak controller] _ in
                Task { @MainActor in
                    controller?.updateIcon()
                }
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

        watcher.start(
            pathProvider: { [settings] in settings.statusFilePath },
            onTick: { [store] path in
                store.reload(from: path)
            }
        )

        Task { @MainActor in
            controller.showOnboardingIfNeeded()
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
}
