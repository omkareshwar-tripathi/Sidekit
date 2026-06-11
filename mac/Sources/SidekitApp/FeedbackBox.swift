import AppKit
import SwiftUI
import SidekitCore

/// Draft state for the quick-feedback box (spec §3): one message, optional 🐞/💡 tag.
/// Sending queues a `feedback` submission; the toast text depends on whether it went
/// out immediately or is parked in the offline spool.
@MainActor
final class FeedbackModel: ObservableObject {
    @Published var message = ""
    @Published var kind: FeedbackKind?          // nil → lands as .other
    @Published private(set) var toast: String?  // non-nil → sent, box is closing

    private let identity: IdentityModel
    private let spool: SubmissionSpool

    init(identity: IdentityModel, spool: SubmissionSpool) {
        self.identity = identity
        self.spool = spool
    }

    var canSend: Bool { RemoteSubmission.validateFeedbackMessage(message) != nil }

    /// Footer transparency line (spec §3: everything sent is visible).
    var footer: String {
        "Sends with: \(identity.email ?? "anonymous") · Sidekit \(AppInfo.appVersion) · \(AppInfo.osVersion)"
    }

    /// Append a dictated transcript, separating with a space when needed (NotesStore rule).
    func appendDictated(_ text: String) {
        if message.isEmpty || message.last!.isWhitespace {
            message += text
        } else {
            message += " " + text
        }
    }

    /// Validate, queue, toast. Returns false when the message isn't sendable.
    func send() async -> Bool {
        guard let body = RemoteSubmission.validateFeedbackMessage(message) else { return false }
        let submission = RemoteSubmission.feedback(
            kind: kind ?? .other, message: body, email: identity.email,
            appVersion: AppInfo.appVersion, osVersion: AppInfo.osVersion)
        let deliveredNow = await spool.enqueue(submission)
        toast = deliveredNow ? "Thanks! 🙌" : "Saved — will send when you're online."
        message = ""
        kind = nil
        return true
    }

    /// Reset the toast for the next open (drafts survive an Esc — only a send clears them).
    func reopened() { toast = nil }
}

/// The 5-second feedback view: text box (placeholder invites dictation), two optional
/// chips, transparency footer, ⌘↩ send / Esc close.
struct FeedbackView: View {
    @ObservedObject var model: FeedbackModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Send Feedback").font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                chip("🐞 Bug", .bug)
                chip("💡 Idea", .feature)
            }

            ZStack(alignment: .topLeading) {
                if model.message.isEmpty {
                    Text("Type — or hold Fn and just say it.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $model.message)
                    .scrollContentBackground(.hidden)
                    .frame(height: 88)
            }
            .padding(DS.Space.sm)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(model.footer)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSend)
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 420)
        .glassCard()   // match the family's dark-glass surface (ShelfView/PillView)
        .overlay {
            if let toast = model.toast {
                Text(toast)
                    .font(DS.Typography.title)
                    .padding(DS.Space.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(KeyCatcher(onEscape: onClose))   // Esc closes without sending (spec §3)
        .tint(DS.Palette.accent)
        .preferredColorScheme(.dark)
    }

    private func chip(_ label: String, _ value: FeedbackKind) -> some View {
        Button(label) { model.kind = (model.kind == value) ? nil : value }
            .buttonStyle(.bordered)
            .tint(model.kind == value ? DS.Palette.accent : .secondary)
    }

    private func send() {
        Task {
            guard await model.send() else { return }
            try? await Task.sleep(for: .milliseconds(900))   // let the toast read
            onClose()
        }
    }
}

/// Invisible NSView that closes the box on Esc (borderless windows don't get
/// `cancelAction` routing for free).
private struct KeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeView {
        let view = EscapeView()
        view.onEscape = onEscape
        return view
    }
    func updateNSView(_ nsView: EscapeView, context: Context) { nsView.onEscape = onEscape }

    final class EscapeView: NSView {
        var onEscape: (() -> Void)?
        // `removeMonitor(_:)` is thread-safe and the token is set once on the main thread before
        // deinit, so the nonisolated deinit may read it to deregister (ShelfPanel uses this pattern).
        private nonisolated(unsafe) var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53, self?.window?.isKeyWindow == true { // 53 = Esc
                    self?.onEscape?()
                    return nil
                }
                return event
            }
        }
        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

/// The feedback box's floating window: borderless glass like the family panels, but
/// **activating and keyable** — the user is deliberately here to type (or dictate), unlike
/// the click-through pill / non-activating shelf.
@MainActor
final class FeedbackBox {
    let model: FeedbackModel
    private let panel: KeyablePanel

    /// Whether dictation should route here (the box is the key window) — see the
    /// RoutingSink wiring in AppController.
    var isKey: Bool { panel.isKeyWindow }

    init(identity: IdentityModel, spool: SubmissionSpool) {
        model = FeedbackModel(identity: identity, spool: spool)
        let canvas = NSRect(x: 0, y: 0, width: 440, height: 240)
        panel = KeyablePanel(contentRect: canvas,
                             styleMask: [.borderless, .fullSizeContentView],
                             backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView:
            FeedbackView(model: model, onClose: { [weak self] in self?.hide() }))
        hosting.frame = canvas
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
    }

    func show() {
        model.reopened()
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                         y: f.midY - panel.frame.height / 2 + 80))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel.orderOut(nil) }

    /// A borderless NSPanel refuses key status by default; the box needs it for typing.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
