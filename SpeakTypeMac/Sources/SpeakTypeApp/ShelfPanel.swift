import AppKit
import SwiftUI

/// The Shelf's floating window: a borderless, **non-activating** (so dropping/clicking never steals
/// focus from the app you're working in), always-on-top panel present on every Space (spec §2.5).
/// Unlike `PillPanel` it is **interactive** (receives clicks/drops) and **summoned** — it starts
/// hidden and is shown via `toggle()`, returning to its remembered position. It's dragged by its
/// header (`WindowDragHandle`), closed by its × button, and fades+rises in/out (Reduce-Motion aware).
@MainActor
final class ShelfPanel {
    private let panel: NSPanel
    private static let frameKey = "shelf.panel.frame"

    init(model: ShelfModel,
         onClose: @escaping () -> Void) {
        // Canvas slightly larger than the 280×360 card so its soft glass shadow never clips; the
        // fixed-size card centers within.
        let canvas = NSRect(x: 0, y: 0, width: 300, height: 384)
        panel = NSPanel(
            contentRect: canvas,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        let hosting = NSHostingView(rootView:
            ShelfView(model: model, onClose: onClose))
        hosting.frame = canvas
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false      // the glass card draws its own shadow
        panel.hidesOnDeactivate = false
        // Dragged via the header's `WindowDragHandle`, not `isMovableByWindowBackground` (which
        // SwiftUI hit-testing swallows). Starts hidden — summoned via `toggle()`.
    }

    var isVisible: Bool { panel.isVisible }

    /// Show if hidden, hide if visible.
    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        restoreFrameOrReposition()
        let settled = panel.frame
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        // Fade in while rising 8pt into place.
        panel.alphaValue = 0
        panel.setFrame(settled.offsetBy(dx: 0, dy: -8), display: false)
        panel.orderFrontRegardless() // show without activating/stealing focus
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(settled, display: true)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        saveFrame() // frame is settled here (show animation has completed)
        if reduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // The completion runs on the main thread; assert isolation to touch the main-actor panel.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1 // reset for the next show
            }
        })
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Restore the user's last position, or place at the top-right of the main screen on first use.
    private func restoreFrameOrReposition() {
        if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
            panel.setFrame(NSRectFromString(saved), display: false)
        } else {
            reposition()
        }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 24, y: area.maxY - size.height - 24))
    }
}
