import Foundation
import SpeakTypeCore

/// One-shot auto-stop timer backed by a main-queue `DispatchSourceTimer`. Fires
/// `onElapsed` on the main thread, where the coordinator lives.
final class SystemAutoStopTimer: AutoStopTimer {
    private var timer: DispatchSourceTimer?

    func start(after delay: Duration, onElapsed: @escaping @Sendable () -> Void) {
        cancel()
        let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + seconds)
        t.setEventHandler(handler: onElapsed)
        t.resume()
        timer = t
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }
}
