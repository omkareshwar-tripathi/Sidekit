import Foundation
import SpeakTypeCore

/// `@MainActor ObservableObject` wrapper over the pure Core `ShelfStore` — keeps Core
/// framework-free (like `NotesModel`/`HistoryModel`) while giving SwiftUI something to observe.
/// Publish-then-mutate (`objectWillChange.send()` before forwarding) so the panel re-renders.
@MainActor
final class ShelfModel: ObservableObject {
    private let store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
        store.pruneExpired(now: Date()) // drop anything that expired while the app was closed
    }

    /// Production store backed by the JSON index file (`shelf.json`).
    convenience init() {
        self.init(store: ShelfStore(persistence: JSONShelfStore()))
    }

    var items: [ShelfItem] { store.items }
    var isEmpty: Bool { store.items.isEmpty }

    func remove(_ id: ShelfItem.ID) { objectWillChange.send(); store.remove(id) }
    func clearAll() { objectWillChange.send(); store.clearAll() }

    /// Expire stale items (called on app activation / periodically by the panel owner).
    func prune() { objectWillChange.send(); store.pruneExpired(now: Date()) }
}
