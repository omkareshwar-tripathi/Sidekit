import Foundation

/// Owns the Shelf's items and the rules for mutating them: add, remove, clear. Kept newest-first
/// (most recent drop on top). Every mutation persists via `ShelfPersisting`. Expiry is layered on
/// in a later brick. Drag-out never mutates the store — the Shelf is reuse-safe by design.
///
/// Pure of UI frameworks (the SwiftUI-observable wrapper and the file-payload adapter come later);
/// `@MainActor` because it's touched from the main-actor drop handlers and the UI.
@MainActor
public final class ShelfStore {
    public private(set) var items: [ShelfItem]
    /// How long items live before auto-expiry. Settable so Settings can change it mid-session.
    public var retention: ShelfRetentionPolicy

    private let persistence: ShelfPersisting
    private let now: () -> Date

    public init(persistence: ShelfPersisting, retention: ShelfRetentionPolicy = .default,
                now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence
        self.retention = retention
        self.now = now
        self.items = persistence.load().sorted { $0.addedAt > $1.addedAt }
    }

    /// Stage a copied payload's metadata on the shelf, stamped now and placed on top. Returns the
    /// new item. (The caller — the payload-store adapter — has already copied the bytes.)
    @discardableResult
    public func add(kind: ShelfItemKind, displayName: String, byteSize: Int64,
                    storedRelativePath: String) -> ShelfItem {
        let item = ShelfItem(kind: kind, displayName: displayName, byteSize: byteSize,
                             addedAt: now(), storedRelativePath: storedRelativePath)
        items.append(item)
        sortAndSave()
        return item
    }

    /// Remove an item by id and persist. No-op (no save) on an unknown id.
    public func remove(_ id: ShelfItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        persistence.save(items)
    }

    /// Empty the shelf and persist.
    public func clearAll() {
        items.removeAll()
        persistence.save(items)
    }

    /// Drop items older than the retention TTL (age strictly greater than `ttl` at `now`), persist
    /// if anything changed, and return the removed items so the caller can delete their payloads.
    /// Returns `[]` (and does not persist) when nothing has expired.
    @discardableResult
    public func pruneExpired(now: Date) -> [ShelfItem] {
        let ttlSeconds = Double(retention.ttl.components.seconds)
        let expired = items.filter { now.timeIntervalSince($0.addedAt) > ttlSeconds }
        guard !expired.isEmpty else { return [] }
        let expiredIDs = Set(expired.map(\.id))
        items.removeAll { expiredIDs.contains($0.id) }
        persistence.save(items)
        return expired
    }

    /// Newest-first; persist the current snapshot.
    private func sortAndSave() {
        items.sort { $0.addedAt > $1.addedAt }
        persistence.save(items)
    }
}
