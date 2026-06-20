// Timing ports — injected so the coordinator's hold-duration guards are
// deterministically testable (mirrors the C# IClock / IAutoStopTimer). Real adapters
// (DispatchTime-backed clock, DispatchSourceTimer) are wired up in a later brick.

/// Monotonic clock. `timestamp()` returns an opaque tick only meaningful when passed
/// back to `elapsed(since:)`.
public protocol MonotonicClock: AnyObject {
    func timestamp() -> UInt64
    func elapsed(since start: UInt64) -> Duration
}

/// One-shot timer for the 60 s auto-stop guard: started when recording begins,
/// cancelled on release. If it elapses first, `onElapsed` ends the hold like a release.
public protocol AutoStopTimer: AnyObject {
    func start(after delay: Duration, onElapsed: @escaping @Sendable () -> Void)
    func cancel()
}
