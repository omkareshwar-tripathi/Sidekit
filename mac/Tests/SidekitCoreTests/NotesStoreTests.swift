import Testing
import Foundation
@testable import SidekitCore

@MainActor
struct NotesStoreTests {

    private func makeSUT(seed: [Note] = []) -> (NotesStore, FakeNotesPersistence) {
        let persistence = FakeNotesPersistence(seed)
        let store = NotesStore(persistence: persistence, now: FakeDates().next)
        return (store, persistence)
    }

    // MARK: - Note.title

    @Test func titleIsFirstNonEmptyTrimmedLine() {
        let n = Note(body: "\n   \n  Hello world  \nsecond line", createdAt: .init(), updatedAt: .init())
        #expect(n.title == "Hello world")
    }

    @Test func titleIsEmptyForBlankBody() {
        let n = Note(body: "   \n\n", createdAt: .init(), updatedAt: .init())
        #expect(n.title == "")
    }

    // MARK: - newNote

    @Test func newNoteInsertsEmptyNoteAtTopAndMakesItActive() {
        let (store, persistence) = makeSUT()
        let note = store.newNote()

        #expect(store.notes.first?.id == note.id)
        #expect(store.notes.first?.body == "")
        #expect(store.activeNote?.id == note.id)
        #expect(persistence.saveCount == 1) // persisted on creation
    }

    // MARK: - append spacing

    @Test func appendToEmptyBodySetsTextVerbatim() {
        let (store, _) = makeSUT()
        let n = store.newNote()
        store.append("hello world ", to: n.id)
        #expect(store.activeNote?.body == "hello world ")
    }

    @Test func appendConcatenatesWhenBodyEndsWithWhitespace() {
        let (store, _) = makeSUT()
        let n = store.newNote()
        store.append("hello ", to: n.id)
        store.append("world", to: n.id) // prior body ends with a space → no extra space
        #expect(store.activeNote?.body == "hello world")
    }

    @Test func appendInsertsSpaceWhenBodyDoesNotEndWithWhitespace() {
        let (store, _) = makeSUT()
        let n = store.newNote()
        store.append("hello", to: n.id) // no trailing space
        store.append("world", to: n.id) // needs a separator
        #expect(store.activeNote?.body == "hello world")
    }

    @Test func appendToUnknownIdIsNoop() {
        let (store, persistence) = makeSUT()
        let before = persistence.saveCount
        store.append("x", to: UUID())
        #expect(store.notes.isEmpty)
        #expect(persistence.saveCount == before)
    }

    // MARK: - ordering

    @Test func appendBumpsNoteToTopByUpdatedAt() {
        let (store, _) = makeSUT()
        let first = store.newNote()   // updatedAt = t1
        let second = store.newNote()  // updatedAt = t2 → top
        #expect(store.notes.first?.id == second.id)

        store.append("hi", to: first.id) // updatedAt = t3 → first jumps to top
        #expect(store.notes.first?.id == first.id)
        #expect(store.notes.last?.id == second.id)
    }

    // MARK: - setBody

    @Test func setBodyReplacesBodyBumpsUpdatedAtAndReorders() {
        let (store, _) = makeSUT()
        let first = store.newNote()
        _ = store.newNote() // second is now active + top
        store.setBody("edited", to: first.id)
        #expect(store.notes.first?.id == first.id)        // jumped to top by updatedAt
        #expect(store.notes.first?.body == "edited")
    }

    @Test func setBodyToUnknownIdIsNoop() {
        let (store, persistence) = makeSUT()
        let before = persistence.saveCount
        store.setBody("x", to: UUID())
        #expect(store.notes.isEmpty)
        #expect(persistence.saveCount == before)
    }

    // MARK: - select / delete

    @Test func selectChangesActiveNote() {
        let (store, _) = makeSUT()
        let a = store.newNote()
        let b = store.newNote()
        #expect(store.activeNote?.id == b.id)
        store.select(a.id)
        #expect(store.activeNote?.id == a.id)
    }

    @Test func deletingActiveNoteFallsBackToTopRemaining() {
        let (store, persistence) = makeSUT()
        let a = store.newNote()
        let b = store.newNote() // active, top
        store.delete(b.id)
        #expect(!store.notes.contains { $0.id == b.id })
        #expect(store.activeNote?.id == a.id) // fell back to remaining
        #expect(persistence.lastSaved.count == 1)
    }

    @Test func deletingLastNoteLeavesNoActive() {
        let (store, _) = makeSUT()
        let a = store.newNote()
        store.delete(a.id)
        #expect(store.notes.isEmpty)
        #expect(store.activeNote == nil)
    }

    // MARK: - load

    @Test func loadsSeededNotesAndActivatesFirst() {
        let seed = [
            Note(body: "one", createdAt: .init(timeIntervalSinceReferenceDate: 1), updatedAt: .init(timeIntervalSinceReferenceDate: 1)),
            Note(body: "two", createdAt: .init(timeIntervalSinceReferenceDate: 2), updatedAt: .init(timeIntervalSinceReferenceDate: 2)),
        ]
        let (store, _) = makeSUT(seed: seed)
        #expect(store.notes.count == 2)
        #expect(store.activeNote?.id == seed.first?.id)
    }
}
