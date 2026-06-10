import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SpeakTypeCore

/// The Shelf surface's content: a glass card with a header, a thumbnail grid of staged items (or an
/// empty state), and a footer (item count + store size + Clear all). Tiles show a QuickLook thumbnail
/// of each item's stored file (kind glyph as the fallback); drag-out + Save-all + per-item ⋯ are still
/// later bricks. The Mirror strip (collapsed by default) now rides just under the header (MIRROR-*).
struct ShelfView: View {
    @ObservedObject var model: ShelfModel

    /// The live-self-view strip at the top of the panel. Owned by `ShelfPanel` (not the view) so the
    /// panel can collapse it / stop the camera on hide and app-deactivate; injected here.
    @ObservedObject var mirror: MirrorModel

    /// Dismiss the panel (the header × button).
    var onClose: () -> Void

    /// Highlights the whole card while a drag hovers over it ("drop to shelve").
    @State private var isDropTarget = false

    /// Generates + caches QuickLook thumbnails for the tiles; one per panel, lives with the view.
    /// `@State` (not `@StateObject`) — we don't observe it; tiles get their image via their own state.
    @State private var thumbnailer = ShelfThumbnailer()

    /// IDs of tiles the user has tap-selected. Drives each tile's accent ring + check badge; the
    /// multi-item drag-out that consumes the selection is the follow-up brick (SHELF-DRAG-OUT-MULTI-B).
    @State private var selection: Set<UUID> = []

    /// Live items currently in the multi-select set. Filtering `model.items` excludes any stale id left
    /// in `selection` by an expiry/prune (so the drag handle never offers a ghost item).
    private var selectedItems: [ShelfItem] { model.items.filter { selection.contains($0.id) } }

    /// Two-column adaptive grid; tiles reflow if the panel is resized later.
    private let columns = [GridItem(.adaptive(minimum: ShelfTile.width), spacing: DS.Space.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Text("Shelf")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            // The header doubles as the window's drag region (a borderless panel has no title bar).
            .background(WindowDragHandle())

            MirrorView(model: mirror)

            if model.isEmpty {
                VStack(spacing: DS.Space.sm) {
                    EqualizerMark(height: 40)
                    Text("Drop files, text, or images here")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    copyingRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.md) {
                        ForEach(model.items) { item in
                            ShelfTile(item: item,
                                      fileURL: model.fileURL(for: item),
                                      thumbnailer: thumbnailer,
                                      isSelected: selection.contains(item.id),
                                      onToggleSelect: { toggleSelection(item.id) },
                                      onRemove: { selection.remove(item.id); model.remove(item.id) },
                                      onCopy: { model.copyToClipboard(item) },
                                      onReveal: { model.revealInFinder(item) })
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                if !selectedItems.isEmpty {
                    ShelfDragHandle(count: selectedItems.count,
                                    files: { dragFiles(for: selectedItems) })
                }
                copyingRow
                ShelfFooter(count: model.items.count,
                            totalBytes: model.totalByteSize,
                            onSaveAll: saveAll,
                            onClearAll: { selection.removeAll(); model.clearAll() })
            }
        }
        .padding(DS.Space.md)
        .frame(width: 280, height: 360)
        .glassCard()
        .overlay(dropHighlight)
        .onDrop(of: [.fileURL, .image, .text],
                delegate: ShelfDropDelegate(model: model, isDropTarget: $isDropTarget,
                                            load: { load($0, into: $1) }))
    }

    /// The panel's drop handling. A `DropDelegate` (not the closure `.onDrop`) so a **self-originated
    /// drag is rejected in `validateDrop`** — then macOS never reports it as targeted and the "drop to
    /// shelve" highlight doesn't light up while one of our own tiles/chips is dragged over the panel
    /// (and `performDrop` is never called, which is also what prevents the self-drop duplicate).
    private struct ShelfDropDelegate: DropDelegate {
        let model: ShelfModel
        @Binding var isDropTarget: Bool
        let load: (NSItemProvider, ShelfModel) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            if ShelfDragMarker.isOnDragPasteboard {
                Diag.log("shelf: ignored self-drag (shelf marker on drag pasteboard)")
                return false
            }
            return true
        }

        func dropEntered(info: DropInfo) { isDropTarget = true }
        func dropExited(info: DropInfo) { isDropTarget = false }

        func performDrop(info: DropInfo) -> Bool {
            isDropTarget = false
            let dragPB = NSPasteboard(name: .drag)

            // 1. Files/folders: read straight from the raw drag pasteboard, which — unlike the
            //    reconstructed NSItemProvider — never loses the file-url. SwiftUI's .onDrop can vend a
            //    dragged file as content bytes only (a PNG as public.png with no file-url, observed),
            //    which strips the real filename and makes drag-out rename the file. The pasteboard
            //    file-urls keep the original name + folder structure; each file is ingested once.
            let dragURLs = (dragPB.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            let freshFiles = dragURLs.filter { !model.isStored($0) }
            if !freshFiles.isEmpty {
                Diag.log("shelf: -> branch=files (pasteboard, n=\(freshFiles.count))")
                freshFiles.forEach { model.ingest(.file($0)) }
                return true
            }

            let providers = info.itemProviders(for: [.fileURL, .image, .text])
            // 2. A raw image selection (dragged from a web page) — decode the bitmap via the provider.
            if let imageProvider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
                load(imageProvider, model)
                return true
            }
            // 3. A text/link selection — the drag pasteboard's plain string is reliable, unlike
            //    NSString-from-provider, which silently no-ops for some text UTIs (plain-text and
            //    markdown both observed dropping nothing).
            if let text = dragPB.string(forType: .string), !text.isEmpty {
                Diag.log("shelf: -> branch=text (pasteboard)")
                model.ingest(.text(text))
                return true
            }
            // 4. File promises / exotic providers the pasteboard didn't expose — per-provider fallback.
            guard !providers.isEmpty else { return false }
            providers.forEach { load($0, model) }
            return true
        }
    }

    /// Shown while dropped bytes are still copying in (a large folder takes a while — spec §7
    /// risk 2), so a slow drop reads as work-in-progress instead of dead silence.
    @ViewBuilder private var copyingRow: some View {
        if model.copyingCount > 0 {
            HStack(spacing: DS.Space.xs) {
                ProgressView()
                    .controlSize(.small)
                Text(model.copyingCount == 1 ? "Copying…" : "Copying \(model.copyingCount) items…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    /// Accent border drawn over the card while a drag hovers it.
    @ViewBuilder private var dropHighlight: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Palette.accent, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    /// Footer "Save all to…": pick a folder, then copy every item's bytes into it. The shelf is a
    /// non-activating panel, so activate first or the open panel can open behind it.
    private func saveAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Save All"
        panel.message = "Choose a folder to save every shelf item into."
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if panel.runModal() == .OK, let directory = panel.url {
            model.saveAll(to: directory)
        }
    }

    /// Toggle a tile's membership in the multi-select set (tap a tile to select / deselect it).
    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Resolve selected items to draggable files (on-disk source + export name + UTI), skipping any
    /// whose bytes are missing. Caller passes live `selectedItems`, so stale selection ids are gone.
    /// Disambiguates duplicate export names within the drag (e.g. several "Image.png") so same-named
    /// snippets don't collide/overwrite on drop.
    private func dragFiles(for items: [ShelfItem]) -> [ShelfDragFile] {
        var usedNames = Set<String>()
        return items.compactMap { item -> ShelfDragFile? in
            guard let url = model.fileURL(for: item),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
            let name = uniqueExportName(shelfExportName(for: item, at: url), taken: &usedNames)
            return ShelfDragFile(url: url, name: name, type: type)
        }
    }

    /// A copy of `name` not already in `taken` — inserts " 2", " 3", … before the extension on a clash
    /// (mirrors `ShelfModel.uniqueDestination`'s naming, but for a name set rather than the filesystem).
    private func uniqueExportName(_ name: String, taken: inout Set<String>) -> String {
        if taken.insert(name).inserted { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if taken.insert(candidate).inserted { return candidate }
            n += 1
        }
    }

    /// Decode one dropped provider and stage it. Routing is decided from the provider's *registered
    /// types*, not `suggestedName` (which is `nil` for Finder drags). Branch order:
    ///   1. **File / folder on disk.** If it has a `public.file-url` (Finder files & folders), copy
    ///      the real on-disk item (correct filename, recursive for folders). Else, if a registered
    ///      *content* type is a genuine file's bytes — non-URL, non-image, and within the text family
    ///      only **source code** (`.sh`/`.py`/`.swift`) — materialize it via `loadFileRepresentation`.
    ///      This is the crux: Finder vends a text-conforming file (e.g. `public.shell-script`) typed
    ///      as its content UTI with **no** `public.file-url`, so a naive text check wrongly grabs the
    ///      bytes as a snippet; routing by `.sourceCode` shelves it as the file. A rich/plain-text
    ///      *selection* (`.rtf`/`.html`/plain-text — not source code) deliberately falls through to 4.
    ///   2. A raw **image** with no file (e.g. dragged from a webpage).
    ///   3. A **web/other URL** (dragged browser link) → shelved as a text snippet of the address.
    ///   4. A raw **text** selection.
    ///
    /// `loadFileRepresentation`'s temp URL and a dragged file-url are both only safe to read inside
    /// the callback, so `ingest` copies the bytes synchronously there (off the main actor).
    nonisolated private func load(_ provider: NSItemProvider, into model: ShelfModel) {
        let ids = provider.registeredTypeIdentifiers
        let hasFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        // A registered type whose bytes are a real file to copy: content, but not a URL, not a raw
        // image, and — within the text family — only source code (so editor selections stay snippets).
        let contentTypeID = ids.first { id in
            guard let t = UTType(id), t.conforms(to: .content),
                  !t.conforms(to: .url), !t.conforms(to: .image) else { return false }
            return t.conforms(to: .text) ? t.conforms(to: .sourceCode) : true
        }
        Diag.log("shelf: drop types=\(ids) name=\(provider.suggestedName ?? "nil") hasFileURL=\(hasFileURL) content=\(contentTypeID ?? "nil")")

        // 1. File / folder on disk.
        if hasFileURL {
            Diag.log("shelf: -> branch=file (file-url)")
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                // A tile dragged out and released back onto the shelf would otherwise re-copy itself
                // as a brand-new item — ignore drops whose file is already one of our payloads.
                if model.isStored(url) { Diag.log("shelf: ignored self-drop (already shelved)"); return }
                model.ingest(.file(url))
            }
            return
        }
        if let contentTypeID {
            Diag.log("shelf: -> branch=file (content \(contentTypeID))")
            _ = provider.loadFileRepresentation(forTypeIdentifier: contentTypeID) { url, _ in
                guard let url else { return }
                model.ingest(.file(url))
            }
            return
        }
        // 2. Raw image (no file).
        if provider.canLoadObject(ofClass: NSImage.self) {
            Diag.log("shelf: -> branch=image")
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                guard let data = pngData(from: image) else {
                    // A vector/PDF-backed NSImage has no bitmap rep to PNG-encode — drop it loudly,
                    // not silently (SHELF-DROP-EDGES a).
                    Diag.log("shelf: image drop has no encodable bitmap representation — skipped")
                    return
                }
                model.ingest(.image(data))
            }
            return
        }
        // 3. Web / other URL (browser link) → text of the address.
        if provider.canLoadObject(ofClass: URL.self) {
            Diag.log("shelf: -> branch=weburl")
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                model.ingest(.text(url.absoluteString))
            }
            return
        }
        // 4. Raw text selection (plain, or rich/markup selections that fell through branch 1).
        if provider.canLoadObject(ofClass: NSString.self) {
            Diag.log("shelf: -> branch=text")
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                model.ingest(.text(text))
            }
        }
    }

    /// PNG-encode a dropped `NSImage` for the payload store (NSImage has no direct `pngData`).
    nonisolated private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// One staged item as a grid tile: a QuickLook thumbnail of its stored file (kind glyph as the
/// fallback) with a name beneath, and a hover-revealed × to remove it. Dragging the tile copies its
/// file out to any app/folder (the item stays — reuse-safe).
private struct ShelfTile: View {
    static let width: CGFloat = 76
    static let height: CGFloat = 64
    /// Reserves two caption lines so wrapped names don't make grid rows uneven (headroom for the
    /// rounded caption face).
    static let nameHeight: CGFloat = 32
    /// Inset of the thumbnail inside the tile's rounded face, so the preview doesn't touch the border.
    static let thumbInset: CGFloat = 4

    let item: ShelfItem
    /// On-disk location of the item's bytes (nil if the store holds none) — the thumbnail source.
    let fileURL: URL?
    let thumbnailer: ShelfThumbnailer
    /// Whether this tile is in the multi-select set — draws the accent ring + corner check badge.
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onRemove: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    /// The image to show: the loaded one, else a synchronous peek at the cache (so a recycled tile with
    /// a warm thumbnail renders it on the first frame instead of flashing the glyph). Nil → kind glyph.
    private var shownThumbnail: NSImage? {
        thumbnail ?? fileURL.flatMap { thumbnailer.cached(for: $0, scale: displayScale) }
    }

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .stroke(DS.Palette.hairline, lineWidth: 1))
                    .frame(width: Self.width, height: Self.height)
                    .overlay {
                        if let thumbnail = shownThumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: Self.width - Self.thumbInset * 2,
                                       height: Self.height - Self.thumbInset * 2)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card - Self.thumbInset / 2,
                                                            style: .continuous))
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .strokeBorder(DS.Palette.accent, lineWidth: 2)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, DS.Palette.accent)
                                .padding(3)
                        }
                    }
                if hovering {
                    HStack(spacing: 2) {
                        Menu {
                            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                            if item.kind == .file || item.kind == .folder {
                                Button("Reveal in Finder", systemImage: "magnifyingglass", action: onReveal)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 16)
                        .help("Item actions")

                        Button { onRemove() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .offset(x: -3, y: 3) // inset just inside the corner so the grid never clips it
                }
            }
            Text(item.displayName)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(width: Self.width, height: Self.nameHeight, alignment: .top)
        }
        // Make the whole tile footprint (incl. the gap + empty caption area) the select/drag hit
        // target, not just the rendered glyphs — same idiom as the header × (otherwise short-name
        // tiles have dead zones the tap never reaches). Child ⋯/× buttons still consume their own taps.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onToggleSelect() }
        .task(id: "\(item.id)@\(displayScale)") {
            guard let fileURL else { return }
            thumbnail = await thumbnailer.thumbnail(
                for: fileURL, scale: displayScale,
                size: CGSize(width: Self.width, height: Self.height))
        }
        .onDrag(dragProvider)
    }

    /// A provider that copies the item's stored file OUT to any app/folder. Registers a **file
    /// representation** (so a folder copies recursively too, unlike `NSItemProvider(contentsOf:)`) with
    /// no `.openInPlace`, so macOS hands the receiver a copy and the shelf's own bytes are never moved
    /// (reuse-safe, spec §4). Also vends the file URL so a stray drop back onto the shelf is recognized
    /// as a self-drop (see `load`). Empty provider when the bytes are gone — the drag carries nothing.
    private func dragProvider() -> NSItemProvider {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return NSItemProvider() }
        let type = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            completion(fileURL, false, nil)
            return nil
        }
        provider.registerObject(fileURL as NSURL, visibility: .all)
        // Stamp the drag as shelf-originated so the panel ignores a self-drop (see ShelfDragMarker —
        // the file-url registration above is lost in pasteboard transit, so it can't serve as the guard).
        provider.registerDataRepresentation(forTypeIdentifier: ShelfDragMarker.typeID,
                                            visibility: .all) { completion in
            completion(ShelfDragMarker.data, nil)
            return nil
        }
        provider.suggestedName = shelfExportName(for: item, at: fileURL)
        return provider
    }

    private var icon: String {
        switch item.kind {
        case .file:   return "doc"
        case .folder: return "folder"
        case .text:   return "text.alignleft"
        case .image:  return "photo"
        }
    }
}

/// Shown above the footer when ≥1 tile is selected: a "Drag N out" chip whose surface is an
/// `NSDraggingSession` source (see `ShelfDragSource`) — drag it into any app/folder to copy every
/// selected item out at once. Sits in the footer, not over the grid, so it never occludes tile hover.
private struct ShelfDragHandle: View {
    let count: Int
    let files: () -> [ShelfDragFile]

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "square.and.arrow.up.on.square")
            Text("Drag \(count) out")
        }
        .font(DS.Typography.caption)
        .foregroundStyle(DS.Palette.textPrimary)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.accent.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Palette.accent.opacity(0.5), lineWidth: 1)))
        .overlay(ShelfDragSource(files: files))
        .help("Drag the \(count) selected item\(count == 1 ? "" : "s") out to any app or folder")
    }
}

/// Footer: item count + total store size on the left, Clear all on the right.
private struct ShelfFooter: View {
    let count: Int
    let totalBytes: Int64
    let onSaveAll: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text("\(count) \(count == 1 ? "item" : "items") · \(sizeText)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Button("Save all to…") { onSaveAll() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Button("Clear all") { onClearAll() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

/// A transparent AppKit view that drags the host window on mouse-down — the reliable way to make a
/// borderless `NSPanel` movable from a SwiftUI region (`isMovableByWindowBackground` is swallowed by
/// SwiftUI hit-testing). Placed behind the header so the title bar acts as the drag handle.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
