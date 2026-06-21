import Foundation

public enum ActionResult: Equatable, Sendable {
    case applied
    case rejected(String)
}

public struct SleepTimer: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case minutes(Int); case endOfChapter }
    public let mode: Mode
    public let fireAt: TimeInterval   // absolute position (s) at which playback stops
    public init(mode: Mode, fireAt: TimeInterval) { self.mode = mode; self.fireAt = fireAt }
}

public struct PlayerState: Equatable, Sendable {
    public var currentBook: Book
    public var isPlaying: Bool
    public var position: TimeInterval
    public var speed: Double
    public var sleepTimer: SleepTimer?

    public init(currentBook: Book, isPlaying: Bool, position: TimeInterval,
                speed: Double, sleepTimer: SleepTimer?) {
        self.currentBook = currentBook; self.isPlaying = isPlaying
        self.position = position; self.speed = speed; self.sleepTimer = sleepTimer
    }

    public static func initial(book: Book) -> PlayerState {
        PlayerState(currentBook: book, isPlaying: false, position: 0, speed: 1.0, sleepTimer: nil)
    }

    /// 0-based index of the chapter whose range contains `position`. Always consistent
    /// with `position`, so it can never drift.
    public var currentChapter: Int {
        currentBook.chapters.lastIndex { position >= $0.startTime } ?? 0
    }
}
