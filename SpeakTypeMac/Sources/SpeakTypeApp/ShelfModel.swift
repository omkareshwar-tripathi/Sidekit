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

    /// Production store backed by the JSON index file (`shelf.json`) + the filesystem payload store
    /// (deletes an item's bytes when it's removed / cleared / expires).
    convenience init() {
        self.init(store: ShelfStore(persistence: JSONShelfStore(), payloads: FileSystemShelfPayloadStore()))
    }

    var items: [ShelfItem] { store.items }
    var isEmpty: Bool { store.items.isEmpty }
    /// Sum of every staged item's byte size — drives the footer's store-size readout.
    var totalByteSize: Int64 { store.items.reduce(0) { $0 + $1.byteSize } }

    func remove(_ id: ShelfItem.ID) { objectWillChange.send(); store.remove(id) }
    func clearAll() { objectWillChange.send(); store.clearAll() }

    /// Stage a dropped source (file/folder/text/image): copy its bytes via the payload store, then
    /// record the item. A failed copy is silently skipped (the adapter logs it) so one bad item in a
    /// multi-item drop never aborts the rest.
    func acceptDrop(_ source: ShelfPayloadSource) {
        objectWillChange.send()
        do { _ = try store.add(from: source) }
        catch { Diag.log("shelf: drop failed (\(error))") }
    }

    /// Expire stale items (called on app activation / periodically by the panel owner).
    func prune() { objectWillChange.send(); store.pruneExpired(now: Date()) }
}
