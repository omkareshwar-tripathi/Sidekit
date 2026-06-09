import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SpeakTypeCore

/// The Shelf surface's content: a glass card with a header, a thumbnail grid of staged items (or an
/// empty state), and a footer (item count + store size + Clear all). Tiles show a kind glyph for now;
/// real QuickLook thumbnails / content previews and drag-in/out + Save-all arrive with the dropped
/// bytes in SHELF-DROP. The Mirror strip is a separate brick (MIRROR-*).
struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    /// Dismiss the panel (the header × button).
    var onClose: () -> Void

    /// Highlights the whole card while a drag hovers over it ("drop to shelve").
    @State private var isDropTarget = false

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
                            ShelfTile(item: item) { model.remove(item.id) }
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
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $isDropTarget) { providers in
            providers.forEach(load)
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

    /// Decode one dropped provider and stage it. Prefer a file URL (the primary citizen), then an
    /// image, then text — so a file drag (which also exposes a name string) is shelved as the file.
    /// Loading is async/off-main; hop back to the main actor before touching the model.
    nonisolated private func load(_ provider: NSItemProvider) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                // A file URL is shelved as the file; a web/other URL (e.g. a dragged browser link)
                // is shelved as a text snippet of the address rather than silently dropped.
                deliver(url.isFileURL ? .file(url) : .text(url.absoluteString))
            }
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage, let data = pngData(from: image) else { return }
                deliver(.image(data))
            }
        } else if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                deliver(.text(text))
            }
        }
    }

    nonisolated private func deliver(_ source: ShelfPayloadSource) {
        Task { @MainActor in model.acceptDrop(source) }
    }

    /// PNG-encode a dropped `NSImage` for the payload store (NSImage has no direct `pngData`).
    nonisolated private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// One staged item as a grid tile: a thumbnail area (kind glyph for now — real QuickLook/preview in
/// SHELF-DROP) with a name beneath, and a hover-revealed × to remove it.
private struct ShelfTile: View {
    static let width: CGFloat = 76
    static let height: CGFloat = 64

    let item: ShelfItem
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .stroke(DS.Palette.hairline, lineWidth: 1))
                    .frame(width: Self.width, height: Self.height)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(DS.Palette.textSecondary))
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
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.width)
        }
        .onHover { hovering = $0 }
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
