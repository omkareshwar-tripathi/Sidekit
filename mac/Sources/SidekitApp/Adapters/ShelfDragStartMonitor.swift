import AppKit

/// Detects a system-wide **file drag** beginning, to auto-summon the Shelf (spec §2 "drop target"
/// state, decisions #4/#6). macOS has no drag-start notification, so this watches global + local
/// `.leftMouseDragged` events (the same Accessibility-gated monitors as `FnKeyMonitor`) and, on each,
/// checks the **drag pasteboard**: a bumped `changeCount` means a new drag session just began.
/// `onFileDragStart` fires once per session, only when the session carries file URLs and did **not**
/// originate from the Shelf itself (`ShelfDragMarker`). `onDragEnd` fires on the left-mouse-up that
/// ends a session we reported. Without Accessibility the monitors silently receive nothing — the
/// hotkey/menu summon path is unaffected (spec §7 risk 1 fallback).
final class ShelfDragStartMonitor {
    var onFileDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var monitors: [Any] = []
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var sessionInFlight = false

    func start() {
        addMonitor(matching: .leftMouseDragged) { [weak self] _ in self?.handleDragged() }
        addMonitor(matching: .leftMouseUp) { [weak self] _ in self?.handleMouseUp() }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }

    deinit { stop() }

    // Global (events while another app is focused) + local (our own UI focused), as in FnKeyMonitor.
    private func addMonitor(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handleDragged() {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != lastChangeCount else { return } // same session (or no drag)
        lastChangeCount = pasteboard.changeCount
        // A fresh drag session just began. Only file drags that didn't start on the Shelf summon it.
        guard pasteboard.availableType(from: [.fileURL]) != nil,
              !ShelfDragMarker.isOnDragPasteboard else { return }
        sessionInFlight = true
        Diag.log("shelf: system file-drag detected")
        onFileDragStart?()
    }

    private func handleMouseUp() {
        guard sessionInFlight else { return }
        sessionInFlight = false
        onDragEnd?()
    }
}
