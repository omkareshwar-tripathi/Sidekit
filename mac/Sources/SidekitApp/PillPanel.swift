import AppKit
import SwiftUI

/// The floating recording pill's window: a borderless, non-activating, always-on-top panel
/// pinned to the bottom-center of the active screen and present on every Space (spec §2.2). It
/// hosts the SwiftUI `PillView` bound to the coordinator state. Click-through for now
/// (informational only) — click-to-open-window arrives with the window-interaction work.
@MainActor
final class PillPanel {
    private let panel: NSPanel

    init(controller: AppController) {
        // A generous fixed canvas so the pill (and its soft shadow) never clips; the pill sizes
        // to its content and is centered within, so bottom-center stays visually centered.
        let canvas = NSRect(x: 0, y: 0, width: 300, height: 90)
        let hosting = NSHostingView(rootView:
            PillView(controller: controller).frame(width: canvas.width, height: canvas.height))
        hosting.frame = canvas

        panel = NSPanel(
            contentRect: canvas,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false           // the glass card draws its own shadow
        panel.ignoresMouseEvents = true   // informational; non-interactive in this version
        panel.hidesOnDeactivate = false

        reposition()
        panel.orderFrontRegardless()      // show without activating/stealing focus
    }

    /// Pin to the bottom-center of the main screen's visible area (above the Dock).
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + 24))
    }
}
