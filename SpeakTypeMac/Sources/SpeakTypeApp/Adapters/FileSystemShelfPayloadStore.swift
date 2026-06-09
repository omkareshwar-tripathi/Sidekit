import Foundation
import SpeakTypeCore

/// `ShelfPayloadStore` backed by the filesystem: each shelved item's copied bytes live in a
/// per-item folder under `~/Library/Application Support/SpeakType/Shelf/<uuid>/…` (same support dir
/// as `shelf.json` — both move together when the app rebrands to "Sidekit").
///
/// This brick implements **deletion** — called by `ShelfStore` whenever an item is removed, the
/// shelf is cleared, or an item expires, so bytes never outlive their index entry. The copy-in path
/// (writing dropped bytes) arrives with drag-in. The item's folder is the first path component of
/// its `storedRelativePath`; removing the whole folder leaves no orphan bytes. Deletion is
/// best-effort — a missing payload (nothing was ever written, e.g. a debug-seeded item) is fine.
///
/// `@unchecked Sendable`: `root` is immutable and deletes are synchronous on the caller (main
/// actor); there's no shared mutable state.
final class FileSystemShelfPayloadStore: ShelfPayloadStore, @unchecked Sendable {
    private let root: URL

    init() {
        self.root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakType/Shelf", isDirectory: true)
    }

    func delete(_ items: [ShelfItem]) {
        for item in items {
            let folder = root.appendingPathComponent(itemFolder(for: item), isDirectory: true)
            do {
                try FileManager.default.removeItem(at: folder)
            } catch CocoaError.fileNoSuchFile {
                // Nothing was written for this item (e.g. a debug-seeded entry) — not an error.
            } catch {
                Diag.log("shelf: payload delete failed for \(item.displayName) (\(error))")
            }
        }
    }

    /// The per-item folder name — the first path component of `storedRelativePath` (the `<uuid>`).
    private func itemFolder(for item: ShelfItem) -> String {
        item.storedRelativePath.split(separator: "/").first.map(String.init) ?? item.storedRelativePath
    }
}
