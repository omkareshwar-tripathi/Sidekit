import AppKit
import SwiftUI
import SidekitCore

/// The soft-gate sign-up sheet (spec §2): email + honest why, skippable, shown at most
/// twice ever (launch 1, and once more at launch ≥5 — `IdentityStore` owns that rule).
struct WelcomeSheet: View {
    @ObservedObject var identity: IdentityModel
    let onClose: () -> Void
    @State private var email = ""

    private var plausible: Bool { EmailCheck.isPlausible(email) }

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            EqualizerMark(height: 44)
            Text("Welcome to Sidekit")
                .font(.title2.weight(.semibold))
            Text("Leave an email so I can send you updates and help when something breaks — nothing else, ever.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { continueTapped() }

            HStack(spacing: DS.Space.md) {
                Button("Skip for now") { onClose() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Continue") { continueTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!plausible)
            }

            Text("Sidekit runs fully on your Mac. This email — and feedback you choose to send — are the only things that ever leave it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.lg)
        .frame(width: 380)
        .glassCard()   // match the family's dark-glass surface (no sheet chrome now)
        .tint(DS.Palette.accent)
        .preferredColorScheme(.dark)
    }

    private func continueTapped() {
        guard identity.submitEmail(email) else { return }
        onClose()
    }
}

/// The welcome's floating window — the spec §2 fallback. The welcome must not depend on the
/// main window existing: Sidekit is menu-bar-centric and launch-at-login suppresses the
/// auto-open, so a window-bound sheet would silently never appear. This panel mirrors
/// `FeedbackBox`'s borderless glass setup so the welcome always shows, window or not.
@MainActor
final class WelcomePanel {
    private let panel: KeyablePanel

    init(identity: IdentityModel) {
        let canvas = NSRect(x: 0, y: 0, width: 420, height: 360)
        panel = KeyablePanel(contentRect: canvas,
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView:
            WelcomeSheet(identity: identity, onClose: { [weak self] in self?.hide() }))
        hosting.frame = canvas
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false      // the glass card draws its own shadow
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
    }

    func show() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                         y: f.midY - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel.orderOut(nil) }

    /// A borderless NSPanel refuses key status by default; the welcome needs it for typing.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
