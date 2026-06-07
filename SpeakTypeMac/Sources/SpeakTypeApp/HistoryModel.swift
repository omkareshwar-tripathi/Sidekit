import Foundation
import SpeakTypeCore

/// SwiftUI-facing observable wrapper over the pure `HistoryStore`. Records each dictation into the
/// trail (newest-first, capped) and persists the snapshot to `history.json`. Mirrors `NotesModel`.
@MainActor
final class HistoryModel: ObservableObject {
    private let store: HistoryStore
    private let persistence: JSONHistoryStore

    @Published private(set) var entries: [DictationHistoryEntry]

    init() {
        let persistence = JSONHistoryStore()
        let store = HistoryStore(entries: persistence.load())
        self.persistence = persistence
        self.store = store
        self.entries = store.entries
    }

    /// Log one dictation (stamped now, fresh id), keep the published copy in sync, and persist.
    func record(_ text: String, _ outcome: DictationOutcome) {
        store.add(DictationHistoryEntry(date: Date(), text: text, outcome: outcome))
        entries = store.entries
        persistence.save(store.entries)
    }
}
