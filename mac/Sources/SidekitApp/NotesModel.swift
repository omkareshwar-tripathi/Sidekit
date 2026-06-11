import Foundation
import Combine
import AppKit
import SidekitCore

/// SwiftUI-facing observable wrapper over the pure `NotesStore` (which stays framework-free in
/// Core). Forwards every mutation and republishes so the window updates; persistence is the
/// debouncing `JSONNotesStore`, flushed on app termination so the last edit is never lost.
@MainActor
final class NotesModel: ObservableObject {
    private let store: NotesStore
    private let persistence: JSONNotesStore

    var notes: [Note] { store.notes }
    var activeID: Note.ID? { store.activeID }
    var activeNote: Note? { store.activeNote }

    init() {
        let persistence = JSONNotesStore()
        self.persistence = persistence
        self.store = NotesStore(persistence: persistence)

        // Force any debounced save to disk before the app exits.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistence.flush() }
        }
    }

    @discardableResult
    func newNote() -> Note { mutate { store.newNote() } }
    func append(_ text: String, to id: Note.ID) { mutate { store.append(text, to: id) } }
    func setBody(_ body: String, for id: Note.ID) { mutate { store.setBody(body, to: id) } }
    func select(_ id: Note.ID) { mutate { store.select(id) } }
    func delete(_ id: Note.ID) { mutate { store.delete(id) } }

    /// Publish-then-mutate so SwiftUI re-renders on the change.
    private func mutate<T>(_ block: () -> T) -> T {
        objectWillChange.send()
        return block()
    }
}
