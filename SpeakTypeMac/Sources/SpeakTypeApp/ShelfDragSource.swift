import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One file to serve in a multi-item drag-out: the on-disk source bytes plus the name + UTI to export
/// it under. Built from the shelf's stored payloads (see `ShelfView.dragFiles`).
struct ShelfDragFile {
    let url: URL
    let name: String
    let type: UTType
}

/// A transparent AppKit overlay that begins a **multi-item file drag** when the user drags it.
///
/// SwiftUI's `.onDrag` vends only ONE provider per drag, so to drag several selected shelf items at
/// once we drop to AppKit's `NSDraggingSession`, which takes one `NSDraggingItem` per file. Each item
/// is an `NSFilePromiseProvider`: the receiver requests the file and we write a **copy** of the stored
/// bytes (folders recursively), so the shelf's own copies are never *moved* out (reuse-safe, spec §4)
/// and text/image snippets keep their export names. The drag session's source operation mask is
/// `.copy`, which forces a copy even on the same volume (a plain file-URL drag would Finder-*move* it).
///
/// This lives behind a small footer "Drag N" handle — deliberately **not** layered over the tile grid —
/// so it occludes nothing and leaves the SwiftUI tiles' hover/tap/single-drag untouched.
struct ShelfDragSource: NSViewRepresentable {
    /// Files to drag, resolved at drag-start so it reflects the current selection; already filtered to
    /// live, on-disk items by the caller.
    let files: () -> [ShelfDragFile]
    /// True while our drag session is in flight — lets the panel's `.onDrop` ignore a self-drop of our
    /// own items back onto it (a file-promise drop isn't caught by the file-URL `isStored` guard).
    let onSessionActive: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DragSourceView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.files = files
        context.coordinator.onSessionActive = onSessionActive
    }

    func makeCoordinator() -> Coordinator { Coordinator(files: files, onSessionActive: onSessionActive) }

    /// The NSDraggingSource for a handle's drag session. Vends the file-promise providers and reports
    /// when the session is in flight (for the panel's self-drop guard). AppKit retains the source for
    /// the whole session, so it outlives a handle that SwiftUI tears down mid-drag; the *promise* work
    /// is on a process-lifetime delegate (below) because the receiver may pull the file even later.
    final class Coordinator: NSObject, NSDraggingSource {
        var files: () -> [ShelfDragFile]
        var onSessionActive: (Bool) -> Void

        init(files: @escaping () -> [ShelfDragFile], onSessionActive: @escaping (Bool) -> Void) {
            self.files = files
            self.onSessionActive = onSessionActive
        }

        /// A promise provider carrying its source `file` in `userInfo`. The delegate is the shared,
        /// process-lifetime `ShelfFilePromiseDelegate` (not `self`) so the promise can still be written
        /// after this Coordinator — tied to the transient drag handle — is gone.
        func makeProvider(for file: ShelfDragFile) -> NSFilePromiseProvider {
            let provider = NSFilePromiseProvider(fileType: file.type.identifier,
                                                 delegate: ShelfFilePromiseDelegate.shared)
            provider.userInfo = file
            return provider
        }

        // MARK: NSDraggingSource — copy-only, so a same-volume drop never MOVES our stored bytes.
        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            // Clear a beat AFTER the drop is handled: a drop back onto our own panel fires the panel's
            // `.onDrop` around this same moment, and it must still see the guard set so it ignores the
            // self-drop. A brief delay covers an `.onDrop` that lands just after `endedAt`, without
            // leaving the panel deaf to real drops for more than a flash. (The guard is *armed*
            // synchronously in `mouseDragged`, not here — `willBeginAt` proved unreliable.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.onSessionActive(false) }
        }
    }

    /// The transparent hit target. On a mouse-drag past a small threshold it builds one dragging item
    /// per file (icon stacked Finder-style) and starts the session; a plain click does nothing.
    private final class DragSourceView: NSView {
        weak var coordinator: Coordinator?
        private var mouseDownPoint: NSPoint?

        // The Shelf is a non-activating panel; without this the first click is spent activating the
        // window instead of beginning a drag, so the first drag-out attempt would be swallowed.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }
        override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownPoint, let coordinator else { return }
            let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            guard moved > 4 else { return } // wait for an intentional drag, not a jittery click
            mouseDownPoint = nil

            let files = coordinator.files()
            guard !files.isEmpty else { return }
            // Arm the self-drop guard synchronously, before the session starts — reliably set before any
            // drop can occur. (`willBeginAt` proved unreliable; reaching `beginDraggingSession` always
            // yields an `endedAt`, so this can't stick true.)
            coordinator.onSessionActive(true)

            let iconSize = NSSize(width: 48, height: 48)
            let items: [NSDraggingItem] = files.enumerated().map { index, file in
                let provider = coordinator.makeProvider(for: file)
                let item = NSDraggingItem(pasteboardWriter: provider)
                let icon = NSWorkspace.shared.icon(forFile: file.url.path)
                icon.size = iconSize
                // Fan the icons out slightly so a multi-item drag reads as a small stack.
                let frame = NSRect(x: CGFloat(index) * 6, y: CGFloat(index) * -6,
                                   width: iconSize.width, height: iconSize.height)
                item.setDraggingFrame(frame, contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: coordinator)
        }
    }
}

/// Writes the file-promise copies for a drag-out. A **process-lifetime singleton** on purpose: the
/// receiver may pull a promised file long after the drag session (and the transient drag handle that
/// started it) is gone, so the delegate must outlive both. It holds no per-drag state — each file rides
/// on its provider's `userInfo` — so one shared instance serves every drag safely. `@unchecked
/// Sendable` is sound: the only stored state is the immutable, thread-safe `queue`.
final class ShelfFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    static let shared = ShelfFilePromiseDelegate()

    /// Serial so a many-folder drag-out copies one at a time rather than saturating disk I/O.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (provider.userInfo as? ShelfDragFile)?.name ?? "item"
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let file = provider.userInfo as? ShelfDragFile else { completionHandler(nil); return }
        do { try FileManager.default.copyItem(at: file.url, to: url); completionHandler(nil) }
        catch { completionHandler(error) }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { queue }
}
