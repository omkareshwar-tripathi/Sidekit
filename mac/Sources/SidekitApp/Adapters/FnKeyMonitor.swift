import AppKit
import SidekitCore

/// Hold-Fn (🌐) push-to-talk source. Watches global `flagsChanged` events for the
/// `.function` modifier toggling on (press) and off (release). If a normal key is pressed
/// while Fn is held, the hold is treated as Fn-used-as-a-modifier and cancelled, not as
/// dictation. Watching global key events needs the Accessibility / Input-Monitoring
/// permission (the same one paste needs); without it the monitors silently receive nothing.
final class FnKeyMonitor: HotkeyListening {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    var onCancelled: (() -> Void)?

    private var monitors: [Any] = []
    private var fnDown = false
    private var aborted = false

    func start() {
        addMonitor(matching: .flagsChanged) { [weak self] event in self?.handleFlags(event) }
        addMonitor(matching: .keyDown) { [weak self] _ in self?.handleOtherKey() }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }

    deinit { stop() }

    // Adds both a global monitor (events while another app is focused) and a local one
    // (events while our own UI is focused), so the Fn key works regardless of focus.
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

    private func handleFlags(_ event: NSEvent) {
        let fnNow = event.modifierFlags.contains(.function)
        if fnNow, !fnDown {
            fnDown = true
            aborted = false
            onPressed?()
        } else if !fnNow, fnDown {
            fnDown = false
            if !aborted { onReleased?() } // an aborted hold was already cancelled
        }
    }

    private func handleOtherKey() {
        guard fnDown, !aborted else { return }
        aborted = true
        onCancelled?()
    }
}
