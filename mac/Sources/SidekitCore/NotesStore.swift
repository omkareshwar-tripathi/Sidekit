import Foundation

/// Owns the scratchpad notes and the rules for mutating them: create, append dictated text,
/// select, delete. Kept newest-updated-first. Every mutation persists via `NotesPersisting`.
///
/// Pure of UI frameworks (the SwiftUI-observable wrapper is added in a later brick); `@MainActor`
/// because it's touched from the main-actor dictation path and the UI.
@MainActor
public final class NotesStore {
    public private(set) var notes: [Note]
    public private(set) var activeID: Note.ID?

    private let persistence: NotesPersisting
    private let now: () -> Date

    public init(persistence: NotesPersisting, now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence
        self.now = now
        self.notes = persistence.load()
        self.activeID = notes.first?.id
    }

    public var activeNote: Note? { notes.first { $0.id == activeID } }

    /// Create an empty note, make it active, and persist. Returns the new note.
    @discardableResult
    public func newNote() -> Note {
        let stamp = now()
        let note = Note(body: "", createdAt: stamp, updatedAt: stamp)
        notes.append(note)
        activeID = note.id
        reorderAndSave()
        return note
    }

    /// Append dictated/typed text to a note's body, inserting a single separating space only
    /// when the existing body doesn't already end in whitespace. Bumps `updatedAt`.
    public func append(_ text: String, to id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let body = notes[index].body
        if body.isEmpty || body.last!.isWhitespace {
            notes[index].body = body + text
        } else {
            notes[index].body = body + " " + text
        }
        notes[index].updatedAt = now()
        reorderAndSave()
    }

    /// Replace a note's whole body (editor edits), bump `updatedAt`, and re-sort newest-first.
    /// No-op on an unknown id.
    public func setBody(_ body: String, to id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].body = body
        notes[index].updatedAt = now()
        reorderAndSave()
    }

    public func select(_ id: Note.ID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    public func delete(_ id: Note.ID) {
        notes.removeAll { $0.id == id }
        if activeID == id { activeID = notes.first?.id }
        persistence.save(notes)
    }

    /// Newest-updated-first; persist the current snapshot.
    private func reorderAndSave() {
        notes.sort { $0.updatedAt > $1.updatedAt }
        persistence.save(notes)
    }
}
