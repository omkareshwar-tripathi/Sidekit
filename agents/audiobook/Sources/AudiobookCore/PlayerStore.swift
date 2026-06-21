import Foundation

public final class PlayerStore {
    public private(set) var state: PlayerState
    private let audio: AudioOutputPort
    private let clock: ClockPort

    public init(book: Book, audio: AudioOutputPort, clock: ClockPort) {
        self.state = .initial(book: book)
        self.audio = audio
        self.clock = clock
        audio.load(book.audioFileName)
    }

    @discardableResult public func play() -> ActionResult {
        guard !state.isPlaying else { return .applied }
        state.isPlaying = true
        audio.play()
        clock.start { [weak self] delta in self?.advance(by: delta) }
        return .applied
    }

    @discardableResult public func pause() -> ActionResult {
        guard state.isPlaying else { return .applied }
        state.isPlaying = false
        audio.pause()
        clock.stop()
        return .applied
    }

    @discardableResult public func skipForward(seconds: TimeInterval = 30) -> ActionResult {
        setPosition(state.position + seconds)
        return .applied
    }

    @discardableResult public func skipBackward(seconds: TimeInterval = 30) -> ActionResult {
        setPosition(state.position - seconds)
        return .applied
    }

    // MARK: - internals

    private func advance(by delta: TimeInterval) {
        setPosition(state.position + delta * state.speed)
        if state.position >= state.currentBook.duration { pause() }
    }

    private func setPosition(_ p: TimeInterval) {
        let clamped = min(max(0, p), state.currentBook.duration)
        state.position = clamped
        audio.seek(to: clamped)
    }
}
