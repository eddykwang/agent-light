import Foundation

@MainActor
final class StatusFileWatcher {
    private var timer: Timer?

    func start(pathProvider: @escaping () -> String, interval: TimeInterval = 1.0, onTick: @escaping (String) -> Void) {
        stop()
        onTick(pathProvider())
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                onTick(pathProvider())
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
