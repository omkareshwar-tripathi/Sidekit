import SwiftUI
import SpeakTypeCore

/// The Shelf surface's content (MVP): a glass card with a header and a simple list of staged items
/// (or an empty state). The rich thumbnail grid, drag-in/out, footer (store size / Save all), and
/// the Mirror strip arrive in later bricks (SHELF-UI / SHELF-DROP / MIRROR-*); this brick is the
/// panel + a legible placeholder so the surface can be summoned, seen, and dismissed.
struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    /// Dismiss the panel (the header × button).
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Text("Shelf")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                if !model.isEmpty {
                    Button("Clear all") { model.clearAll() }
                        .buttonStyle(.plain)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
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
                    VStack(spacing: DS.Space.xs) {
                        ForEach(model.items) { item in
                            ShelfRow(item: item) { model.remove(item.id) }
                        }
                    }
                }
            }
        }
        .padding(DS.Space.md)
        .frame(width: 280, height: 360)
        .glassCard()
    }
}

/// One staged item: a kind glyph, its name, and a remove button.
private struct ShelfRow: View {
    let item: ShelfItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Palette.textSecondary)
            Text(item.displayName)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Button { onRemove() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
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
