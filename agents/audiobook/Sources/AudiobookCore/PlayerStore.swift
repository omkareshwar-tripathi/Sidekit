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

    @discardableResult public func nextChapter() -> ActionResult {
        let chapters = state.currentBook.chapters
        let next = state.currentChapter + 1
        guard next < chapters.count else { return .applied }   // already last → no-op
        setPosition(chapters[next].startTime)
        return .applied
    }

    @discardableResult public func previousChapter() -> ActionResult {
        let prev = state.currentChapter - 1
        guard prev >= 0 else { return .applied }               // already first → no-op
        setPosition(state.currentBook.chapters[prev].startTime)
        return .applied
    }

    /// `number` is 1-based (natural language "chapter 3").
    @discardableResult public func goToChapter(_ number: Int) -> ActionResult {
        let chapters = state.currentBook.chapters
        let index = number - 1
        guard chapters.indices.contains(index) else {
            return .rejected("chapter \(number) out of range (1...\(chapters.count))")
        }
        setPosition(chapters[index].startTime)
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
