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

    @discardableResult public func setSpeed(_ rate: Double) -> ActionResult {
        guard (0.5...3.0).contains(rate) else { return .rejected("speed \(rate) outside 0.5...3.0") }
        state.speed = rate
        audio.setRate(rate)
        return .applied
    }

    @discardableResult public func setSleepTimer(minutes: Int) -> ActionResult {
        guard minutes > 0 else { return .rejected("minutes must be positive") }
        state.sleepTimer = SleepTimer(mode: .minutes(minutes),
                                      fireAt: state.position + Double(minutes) * 60)
        return .applied
    }

    @discardableResult public func setSleepTimerEndOfChapter() -> ActionResult {
        let chapters = state.currentBook.chapters
        let next = state.currentChapter + 1
        let fireAt = next < chapters.count ? chapters[next].startTime : state.currentBook.duration
        state.sleepTimer = SleepTimer(mode: .endOfChapter, fireAt: fireAt)
        return .applied
    }

    @discardableResult public func cancelSleepTimer() -> ActionResult {
        state.sleepTimer = nil
        return .applied
    }

    @discardableResult public func switchBook(title: String) -> ActionResult {
        let q = title.lowercased()
        let matches = SampleLibrary.books.filter {
            $0.title.lowercased() == q || $0.title.lowercased().contains(q)
        }
        guard matches.count == 1, let book = matches.first else {
            return .rejected("no unique book matches \"\(title)\"")
        }
        let wasPlaying = state.isPlaying
        if wasPlaying { pause() }
        state = .initial(book: book)
        audio.load(book.audioFileName)
        return .applied
    }

    // MARK: - internals

    private func advance(by delta: TimeInterval) {
        setPosition(state.position + delta * state.speed)
        if let timer = state.sleepTimer, state.position >= timer.fireAt {
            state.sleepTimer = nil
            pause()
            return
        }
        if state.position >= state.currentBook.duration { pause() }
    }

    private func setPosition(_ p: TimeInterval) {
        let clamped = min(max(0, p), state.currentBook.duration)
        state.position = clamped
        audio.seek(to: clamped)
    }
}
