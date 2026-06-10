import AppKit
import SwiftUI
import AVFoundation

/// The Mirror's full-display overlay: a borderless, **non-activating**, always-on-top panel sized to
/// the active screen, showing the mirrored self-view edge to edge. Created lazily on the first
/// full-screen entry and driven entirely by `MirrorModel` (shown while `state == .fullScreen`, hidden
/// otherwise). Exit via the ✕, a **click anywhere**, or **Esc** — all call `onExit`, which routes back
/// to the windowed `.expanded` view. The Esc monitor is installed only while the overlay is shown and
/// torn down on hide, so it never swallows Esc elsewhere (spec risk #3). Its window level sits above
/// the Shelf's floating panel and the menu bar (a deliberate full-display mirror, spec risk #4).
@MainActor
final class MirrorOverlayPanel {
    private let panel: NSPanel
    private var escMonitors: [Any] = []
    /// Invoked by the ✕, a background click, or Esc; held only while the overlay is shown.
    private var onExit: (() -> Void)?

    init() {
        panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver   // above the Shelf's `.floating` panel and the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
    }

    /// Show the overlay on the Mirror's screen, hosting a fresh mirrored preview layer.
    func show(previewLayer: AVCaptureVideoPreviewLayer, onExit: @escaping () -> Void) {
        self.onExit = onExit
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? panel.frame
        panel.setFrame(frame, display: false)

        let hosting = NSHostingView(rootView:
            MirrorOverlayView(previewLayer: previewLayer, onExit: onExit))
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hosting

        installEscMonitor()
        orderFrontAnimated()
    }

    /// Hide the overlay and release the hosted preview layer (so no stray layer retains the session).
    func hide() {
        removeEscMonitor()
        onExit = nil
        if reduceMotion {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // If a re-show landed during the fade, `onExit` is non-nil again — skip the teardown
                // so we don't order the freshly-shown overlay back out (stale-completion race).
                guard self.onExit == nil else { return }
                self.panel.orderOut(nil)
                self.panel.contentView = nil   // drop the preview layer's host
                self.panel.alphaValue = 1      // reset for the next show
            }
        })
    }

    private func orderFrontAnimated() {
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()   // show without activating / stealing focus
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    // Esc-to-exit: a non-activating panel may not get key events through the responder chain, so
    // watch global + local `.keyDown` (keyCode 53 = Escape) just while the overlay is up — the same
    // monitor pattern as FnKeyMonitor, scoped to the overlay's lifetime.
    private func installEscMonitor() {
        removeEscMonitor()   // idempotent — never stack a second pair if show() is re-entered
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { self?.onExit?() }
        }) {
            escMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.onExit?()
            return nil   // swallow Esc so AppKit doesn't beep
        }) {
            escMonitors.append(local)
        }
    }

    private func removeEscMonitor() {
        for m in escMonitors { NSEvent.removeMonitor(m) }
        escMonitors.removeAll()
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// The full-screen overlay's content: the mirrored preview filling the screen, a transparent
/// click-catcher layered on top that exits on a tap anywhere, and the ✕ control above *that*. Built
/// with `.overlay` chaining (not ZStack sibling order) so each control is structurally guaranteed to
/// win its own taps over the full-bleed catcher — and so the ☀ edge-light toggle (MIRROR-EDGELIGHT)
/// can be added as another top overlay without the catcher swallowing it (spec risk #2). The ☀ toggle
/// + bright frame land in MIRROR-EDGELIGHT.
private struct MirrorOverlayView: View {
    let previewLayer: AVCaptureVideoPreviewLayer
    let onExit: () -> Void

    var body: some View {
        CameraPreview(layer: previewLayer)
            .ignoresSafeArea()
            // A tap anywhere exits full screen; controls layered after this win their own taps.
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onExit() }
            }
            .overlay(alignment: .topTrailing) {
                Button { onExit() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(DS.Space.lg)
                .help("Exit full screen")
            }
    }
}
