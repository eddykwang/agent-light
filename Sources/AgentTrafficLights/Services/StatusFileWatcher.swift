import Foundation

@MainActor
final class StatusFileWatcher {
    private var timer: Timer?

    func start(pathProvider: @escaping () -> String, interval: TimeInterval = 1.0, onTick: @escaping (String) -> Void) {
        stop()
        onTick(pathProvider())
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            onTick(pathProvider())
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
