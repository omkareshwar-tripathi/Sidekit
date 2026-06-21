import Foundation
@testable import AudiobookCore

final class FakeAudioOutput: AudioOutputPort {
    private(set) var loaded: String?
    private(set) var isPlaying = false
    private(set) var seekedTo: TimeInterval?
    private(set) var rate: Double = 1.0
    private(set) var playCount = 0
    private(set) var pauseCount = 0

    func load(_ fileName: String) { loaded = fileName }
    func play() { isPlaying = true; playCount += 1 }
    func pause() { isPlaying = false; pauseCount += 1 }
    func seek(to seconds: TimeInterval) { seekedTo = seconds }
    func setRate(_ rate: Double) { self.rate = rate }
}

final class FakeClock: ClockPort {
    private var onTick: ((TimeInterval) -> Void)?
    private(set) var running = false
    func start(onTick: @escaping (TimeInterval) -> Void) { self.onTick = onTick; running = true }
    func stop() { running = false }
    /// Test helper: advance logical time by `delta` wall-seconds (only fires while running).
    func tick(_ delta: TimeInterval) { if running { onTick?(delta) } }
}
