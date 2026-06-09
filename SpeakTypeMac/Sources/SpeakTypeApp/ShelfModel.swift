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

    /// Expire stale items (called on app activation / periodically by the panel owner).
    func prune() { objectWillChange.send(); store.pruneExpired(now: Date()) }

#if DEBUG
    // TEMP (remove in SHELF-DROP): seeds sample items so the grid/footer can be verified on the
    // Mac before drag-in exists. DEBUG-only so it can never reach a release/notarized build. No real
    // payload bytes — tiles fall back to kind glyphs.
    func seedSamples() {
        objectWillChange.send()
        store.add(kind: .file,  displayName: "Quarterly-report.pdf", byteSize: 248_000, storedRelativePath: "sample/1")
        store.add(kind: .image, displayName: "Screenshot.png",       byteSize: 1_240_000, storedRelativePath: "sample/2")
        store.add(kind: .text,  displayName: "Meeting notes",        byteSize: 1_400, storedRelativePath: "sample/3")
        store.add(kind: .folder, displayName: "Design assets",       byteSize: 5_600_000, storedRelativePath: "sample/4")
    }
#endif
}
