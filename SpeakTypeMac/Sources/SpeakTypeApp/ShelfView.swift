import SwiftUI
import SpeakTypeCore

/// The Shelf surface's content: a glass card with a header, a thumbnail grid of staged items (or an
/// empty state), and a footer (item count + store size + Clear all). Tiles show a kind glyph for now;
/// real QuickLook thumbnails / content previews and drag-in/out + Save-all arrive with the dropped
/// bytes in SHELF-DROP. The Mirror strip is a separate brick (MIRROR-*).
struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    /// Dismiss the panel (the header × button).
    var onClose: () -> Void

    /// Two-column adaptive grid; tiles reflow if the panel is resized later.
    private let columns = [GridItem(.adaptive(minimum: ShelfTile.width), spacing: DS.Space.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Text("Shelf")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                #if DEBUG
                // TEMP (remove in SHELF-DROP): seed sample items so the grid is verifiable before
                // drag-in exists. DEBUG-only — gone in release/notarized builds.
                Button { model.seedSamples() } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add sample items (temporary)")
                #endif
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
