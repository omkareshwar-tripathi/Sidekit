import Foundation
import SpeakTypeCore

/// Monotonic clock backed by `DispatchTime` (mirrors the C# Stopwatch-based clock).
final class SystemClock: MonotonicClock {
    func timestamp() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    func elapsed(since start: UInt64) -> Duration {
        .nanoseconds(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds &- start))
    }
}
