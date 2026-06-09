import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SpeakTypeCore

/// The Shelf surface's content: a glass card with a header, a thumbnail grid of staged items (or an
/// empty state), and a footer (item count + store size + Clear all). Tiles show a QuickLook thumbnail
/// of each item's stored file (kind glyph as the fallback); drag-out + Save-all + per-item ⋯ are still
/// later bricks. The Mirror strip is a separate brick (MIRROR-*).
struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    /// Dismiss the panel (the header × button).
    var onClose: () -> Void

    /// Highlights the whole card while a drag hovers over it ("drop to shelve").
    @State private var isDropTarget = false

    /// Generates + caches QuickLook thumbnails for the tiles; one per panel, lives with the view.
    /// `@State` (not `@StateObject`) — we don't observe it; tiles get their image via their own state.
    @State private var thumbnailer = ShelfThumbnailer()

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

            if model.isEmpty {
                VStack(spacing: DS.Space.sm) {
                    EqualizerMark(height: 40)
                    Text("Drop files, text, or images here")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.md) {
                        ForEach(model.items) { item in
                            ShelfTile(item: item,
                                      fileURL: model.fileURL(for: item),
                                      thumbnailer: thumbnailer) { model.remove(item.id) }
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                ShelfFooter(count: model.items.count,
                            totalBytes: model.totalByteSize,
                            onClearAll: { model.clearAll() })
            }
        }
        .padding(DS.Space.md)
        .frame(width: 280, height: 360)
        .glassCard()
        .overlay(dropHighlight)
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $isDropTarget) { [model] providers in
            providers.forEach { load($0, into: model) }
            return true
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
                guard let image = object as? NSImage, let data = pngData(from: image) else { return }
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
/// fallback) with a name beneath, and a hover-revealed × to remove it.
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
    let onRemove: () -> Void
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
                if hovering {
                    Button { onRemove() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
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
        .onHover { hovering = $0 }
        .task(id: "\(item.id)@\(displayScale)") {
            guard let fileURL else { return }
            thumbnail = await thumbnailer.thumbnail(
                for: fileURL, scale: displayScale,
                size: CGSize(width: Self.width, height: Self.height))
        }
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

/// Footer: item count + total store size on the left, Clear all on the right.
private struct ShelfFooter: View {
    let count: Int
    let totalBytes: Int64
    let onClearAll: () -> Void

    var body: some View {
        HStack {
            Text("\(count) \(count == 1 ? "item" : "items") · \(sizeText)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
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
