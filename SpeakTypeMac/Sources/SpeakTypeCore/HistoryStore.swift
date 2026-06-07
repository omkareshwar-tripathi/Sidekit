import Foundation

/// Owns the dictation trail: the most recent entries, newest-first, capped at `maxEntries`. Each
/// `add` prepends and trims the oldest overflow. Pure of UI frameworks and of I/O — the observable
/// wrapper and on-disk persistence live in the app target. Mirrors `NotesStore`'s shape.
@MainActor
public final class HistoryStore {
    /// The most a trail keeps; older entries are dropped on overflow.
    public static let maxEntries = 50

    public private(set) var entries: [DictationHistoryEntry]

    public init(entries: [DictationHistoryEntry] = []) {
        self.entries = Array(entries.prefix(Self.maxEntries))
    }

    /// Prepend the newest entry and trim back to the cap, dropping the oldest.
    public func add(_ entry: DictationHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}
