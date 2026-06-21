import Foundation
import AudiobookCore

final class SystemClock: ClockPort {
    private var timer: Timer?
    private var last: Date?

    func start(onTick: @escaping (TimeInterval) -> Void) {
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let last = self.last else { return }
            let now = Date()
            onTick(now.timeIntervalSince(last))
            self.last = now
        }
    }

    func stop() { timer?.invalidate(); timer = nil; last = nil }
}
