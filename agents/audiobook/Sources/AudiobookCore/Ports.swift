import Foundation

/// Real audio output. The core drives this as a side effect; verification reads
/// PlayerState, not this port.
public protocol AudioOutputPort: AnyObject {
    func load(_ fileName: String)
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setRate(_ rate: Double)
}

/// Drives logical playback time. `onTick` delivers elapsed wall-seconds since the last tick;
/// the core multiplies by `speed` to advance `position`.
public protocol ClockPort: AnyObject {
    func start(onTick: @escaping (TimeInterval) -> Void)
    func stop()
}
