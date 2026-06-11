import Foundation
import SpeakTypeCore

/// `ShelfPayloadStore` backed by the filesystem: each shelved item's copied bytes live in a
/// per-item folder under `~/Library/Application Support/Sidekit/Shelf/<uuid>/…` (same support dir
/// as `shelf.json`, via `AppPaths.applicationSupport`).
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
        self.root = AppPaths.applicationSupport.appendingPathComponent("Shelf", isDirectory: true)
    }

    /// Copy a dropped source into a fresh `<uuid>/` folder under the store root and report back its
    /// metadata. The folder name (the `<uuid>`) is the first path component of `storedRelativePath`,
    /// matching what `delete(_:)` removes — so the bytes are always reachable and cleanable.
    /// The copy + size walk run **off** the main actor (`ShelfModel.ingest` is `nonisolated` and
    /// calls this inside the drop callback), so a big folder doesn't freeze the UI.
    /// TODO(SHELF-POLISH): show copy progress / allow cancel for large folders (spec §7 risk 2).
    func store(_ source: ShelfPayloadSource) throws -> StoredPayload {
        let id = UUID().uuidString
        let folder = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        switch source {
        case .file(let url):
            let name = url.lastPathComponent
            let dest = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: dest)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return StoredPayload(kind: isDir ? .folder : .file, displayName: name,
                                 byteSize: byteSize(of: dest), storedRelativePath: "\(id)/\(name)")
        case .text(let text):
            let name = "snippet.txt"
            let data = Data(text.utf8)
            try data.write(to: folder.appendingPathComponent(name))
            return StoredPayload(kind: .text, displayName: snippetTitle(text),
                                 byteSize: Int64(data.count), storedRelativePath: "\(id)/\(name)")
        case .image(let data):
            let name = "image.png"
            try data.write(to: folder.appendingPathComponent(name))
            return StoredPayload(kind: .image, displayName: "Image", byteSize: Int64(data.count),
                                 storedRelativePath: "\(id)/\(name)")
        }
    }

    /// The on-disk location of a stored item's bytes — the store root joined with its relative path
    /// (drives tile QuickLook thumbnails). Not existence-checked: QuickLook simply yields no thumbnail
    /// if the bytes are gone, and the tile keeps its kind glyph.
    func url(for item: ShelfItem) -> URL? {
        root.appendingPathComponent(item.storedRelativePath)
    }

    /// True when `url` lives inside the store root — i.e. it's one of our own copied payloads. The
    /// trailing slash stops a sibling like `…/ShelfOther` from matching `…/Shelf`.
    func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
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

    /// Bytes on disk for a copied file, or the recursive sum for a folder (drives the footer size).
    /// One path: the URL's own file size plus every descendant's (directories report no size, so a
    /// plain file yields just its own bytes and an empty enumerator).
    private func byteSize(of url: URL) -> Int64 {
        func fileSize(_ u: URL) -> Int64 {
            Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total = fileSize(url)
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in walker { total += fileSize(file) }
        }
        return total
    }

    /// A short label for a text snippet: its first non-empty line, trimmed and capped.
    private func snippetTitle(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Text snippet" : String(trimmed.prefix(40))
    }
}
