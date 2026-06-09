import Foundation
import SpeakTypeCore

/// `@MainActor ObservableObject` wrapper over the pure Core `ShelfStore` — keeps Core
/// framework-free (like `NotesModel`/`HistoryModel`) while giving SwiftUI something to observe.
/// Synchronous mutators publish-then-mutate (`objectWillChange.send()` before forwarding); `ingest`
/// copies off the main actor first, then publishes + records on the main actor. Panel re-renders either way.
@MainActor
final class ShelfModel: ObservableObject {
    private let store: ShelfStore
    /// The same payload store the `ShelfStore` deletes through — held here too so drag-in can copy
    /// bytes off the main actor (see `ingest`). `nonisolated`/`Sendable`, so safe to touch off-main.
    private let payloadStore: ShelfPayloadStore

    init(store: ShelfStore, payloadStore: ShelfPayloadStore = NoopShelfPayloadStore()) {
        self.store = store
        self.payloadStore = payloadStore
        store.pruneExpired(now: Date()) // drop anything that expired while the app was closed
    }

    /// Production store backed by the JSON index file (`shelf.json`) + the filesystem payload store
    /// (one instance copies bytes in on drop and deletes them on remove / clear / expire).
    convenience init() {
        let payloads = FileSystemShelfPayloadStore()
        self.init(store: ShelfStore(persistence: JSONShelfStore(), payloads: payloads), payloadStore: payloads)
    }

    var items: [ShelfItem] { store.items }
    var isEmpty: Bool { store.items.isEmpty }
    /// Sum of every staged item's byte size — drives the footer's store-size readout.
    var totalByteSize: Int64 { store.items.reduce(0) { $0 + $1.byteSize } }

    /// The on-disk URL of an item's copied bytes (nil if the store holds none) — drives tile thumbnails.
    func fileURL(for item: ShelfItem) -> URL? { payloadStore.url(for: item) }

    func remove(_ id: ShelfItem.ID) { objectWillChange.send(); store.remove(id) }
    func clearAll() { objectWillChange.send(); store.clearAll() }

    /// Stage a dropped source (file/folder/text/image): copy its bytes via the payload store, then
    /// record the item. **`nonisolated`** so it can run inside an `NSItemProvider` load callback — a
    /// dropped file's `loadFileRepresentation` temp URL is only valid there, so the copy must happen
    /// synchronously off the main actor; only the model mutation hops back to main. A failed copy is
    /// logged and skipped, so one bad item never aborts the rest of a multi-item drop.
    nonisolated func ingest(_ source: ShelfPayloadSource) {
        do {
            let payload = try payloadStore.store(source)
            Task { @MainActor in
                objectWillChange.send()
                store.record(payload)
            }
        } catch {
            Diag.log("shelf: drop failed (\(error))")
        }
    }

    /// Expire stale items (called on app activation / periodically by the panel owner).
    func prune() { objectWillChange.send(); store.pruneExpired(now: Date()) }
}
