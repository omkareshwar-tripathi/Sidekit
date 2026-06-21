import Foundation
import AudiobookCore

// Safe: SystemClock is only ever started/stopped and ticked on the main run loop.
final class SystemClock: ClockPort, @unchecked Sendable {
    private var timer: Timer?
    private var last: Date?
    private var onTick: ((TimeInterval) -> Void)?

    func start(onTick: @escaping (TimeInterval) -> Void) {
        self.onTick = onTick
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.fire()
        }
    }

    private func fire() {
        guard let last else { return }
        let now = Date()
        onTick?(now.timeIntervalSince(last))
        self.last = now
    }

    func stop() { timer?.invalidate(); timer = nil; last = nil; onTick = nil }
}
