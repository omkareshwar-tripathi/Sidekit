import AppKit
import SwiftUI
import SidekitCore

/// Observable bridge over `IntelligenceSession` for the scratchpad (spec §3): input draft,
/// result, status line, tone persistence, clipboard prefill, dictation append.
@MainActor
final class IntelligencePanelModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var result: String?
    @Published private(set) var sessionState: IntelligenceSession.State
    @Published private(set) var errorText: String?
    @Published var tone: IntelligenceTone {
        didSet { UserDefaults.standard.set(tone.rawValue, forKey: Self.toneKey) }
    }
    @Published private(set) var focusToken = 0
    @Published private(set) var copied = false

    private static let toneKey = "IntelligenceTone"
    let session: IntelligenceSession
    private let provisioner: any ModelProvisioning

    init(session: IntelligenceSession, provisioner: any ModelProvisioning) {
        self.session = session
        self.provisioner = provisioner
        self.sessionState = session.state
        self.tone = UserDefaults.standard.string(forKey: Self.toneKey)
            .flatMap(IntelligenceTone.init(rawValue:)) ?? .keepTone
        session.onStateChanged = { [weak self] state in self?.sessionState = state }
        session.onResult = { [weak self] text in
            self?.result = text
            self?.errorText = nil
        }
        session.onError = { [weak self] message in
            self?.errorText = message
            Diag.log("intelligence: \(message)")   // spec §9: every failure logged
        }
    }

    var busy: Bool {
        sessionState == .loading || sessionState == .generating
    }

    /// Chips run only from ready/warm (spec §5) — and only with text present (view-side).
    var chipsEnabled: Bool { sessionState == .ready || sessionState == .warm }

    /// The honest status line (spec §3/§5). nil → line hidden.
    var statusText: String? {
        if let errorText { return errorText }
        switch sessionState {
        case .downloading(let p): return "Downloading… \(Int(p * 100))%"
        case .loading: return "Warming up…"
        case .generating: return "Drafting…"
        case .needsModel, .ready, .warm: return nil
        }
    }

    func run(_ chip: IntelligenceChip) {
        errorText = nil
        session.run(chip: chip, tone: tone, input: input)
    }

    func cancel() { session.cancelGeneration() }
    func download() { errorText = nil; session.requestDownload() }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// Iterate: the result becomes the next input (spec §3 — the editor is never
    /// overwritten BY a generation; only this explicit tap moves text).
    func useAsInput() {
        guard let result else { return }
        input = result
        self.result = nil
    }

    func clear() {
        input = ""
        result = nil
        errorText = nil
    }

    /// Settings → Remove model (spec §6): delete the files, drop the session to needsModel.
    func removeModel() {
        do {
            try provisioner.remove()
            session.modelRemoved()
        } catch {
            errorText = "Couldn't remove the model files."
        }
    }

    /// Append a dictated transcript (NotesStore separator rule — FeedbackModel precedent).
    func appendDictated(_ text: String) {
        if input.isEmpty || input.last!.isWhitespace { input += text }
        else { input += " " + text }
    }

    /// Per open: clear stale toasts/errors, optionally prefill from the clipboard
    /// (Polish entry, spec §2 — whitespace-trim only, over-cap shows the honest message).
    func reopened(prefillFromClipboard: Bool, preselect: IntelligenceChip?) {
        errorText = nil
        copied = false
        if prefillFromClipboard,
           let clip = NSPasteboard.general.string(forType: .string) {
            let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                input = trimmed
                result = nil
                if case .tooLong = IntelligencePrompt.check(trimmed) {
                    errorText = IntelligencePrompt.tooLongMessage
                }
            }
        }
        highlightedChip = preselect
        focusToken += 1
    }

    /// The Polish pill entry highlights its chip (spec §2) — visual hint only; the tap runs it.
    @Published var highlightedChip: IntelligenceChip?
}

/// The scratchpad (spec §3): editor → chips → tone → result → status. Esc closes, draft survives.
struct IntelligenceView: View {
    @ObservedObject var model: IntelligencePanelModel
    let onClose: () -> Void
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Scratchpad").font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                if !model.input.isEmpty || model.result != nil {
                    Button("Clear") { model.clear() }.buttonStyle(.plain)
                        .font(DS.Typography.caption).foregroundStyle(.tertiary)
                }
                // Visible close affordance (user M11 feedback — Esc alone is undiscoverable).
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

            ZStack(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("Type — or hold Fn and just say it.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $model.input)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(height: 130)
            }
            .padding(DS.Space.sm)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: DS.Space.sm) {
                ForEach(IntelligenceChip.allCases, id: \.self) { chip in
                    Button(chip.label) { model.run(chip) }
                        .buttonStyle(.bordered)
                        .tint(model.highlightedChip == chip ? DS.Palette.accent : .secondary)
                        .disabled(model.input.isEmpty || !model.chipsEnabled)
                }
            }

            Picker("Tone", selection: $model.tone) {
                ForEach(IntelligenceTone.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if let result = model.result {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    // Sizes to the text until the cap, then scrolls — the panel grows with the
                    // result and the Copy row below stays visible (user M11 feedback: the old
                    // fixed 160 pt strip in a fixed 420 pt window clipped long output).
                    ViewThatFits(in: .vertical) {
                        resultText(result)
                        ScrollView { resultText(result) }
                    }
                    .frame(maxHeight: 300)
                    HStack {
                        Button(model.copied ? "Copied ✓" : "Copy") { model.copyResult() }
                            .buttonStyle(.borderedProminent)
                        Button("Use as input") { model.useAsInput() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(DS.Space.sm)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }

            statusLine
        }
        .padding(DS.Space.lg)
        .frame(width: 500)
        .glassCard()
        .background(IntelligenceKeyCatcher(onEscape: onClose))
        .onAppear { editorFocused = true }
        .onChange(of: model.focusToken) { editorFocused = true }
        .tint(DS.Palette.accent)
        .preferredColorScheme(.dark)
        // Hug the bottom of the tall transparent canvas: the card sits just above the pill
        // and grows UPWARD as content grows; the rest of the window is fully transparent,
        // so per-pixel hit testing passes clicks through it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func resultText(_ result: String) -> some View {
        Text(result).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var statusLine: some View {
        if model.sessionState == .needsModel {
            HStack {
                if let error = model.statusText {
                    Text(error).font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.statusText == nil ? "Download model (≈0.9 GB, one time)" : "Retry") {
                    model.download()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let status = model.statusText {
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(status).font(DS.Typography.caption).foregroundStyle(.secondary)
                Spacer()
                if model.sessionState == .generating {
                    Button("Cancel") { model.cancel() }.buttonStyle(.bordered)
                }
            }
        }
    }
}

/// Esc-to-close for the borderless panel (FeedbackBox's KeyCatcher, same shape).
private struct IntelligenceKeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeView {
        let view = EscapeView()
        view.onEscape = onEscape
        return view
    }
    func updateNSView(_ nsView: EscapeView, context: Context) { nsView.onEscape = onEscape }

    final class EscapeView: NSView {
        var onEscape: (() -> Void)?
        private nonisolated(unsafe) var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53, self?.window?.isKeyWindow == true {
                    self?.onEscape?()
                    return nil
                }
                return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// The scratchpad's floating window: borderless glass, activating and keyable (the user is
/// deliberately here to type/dictate) — FeedbackBox's species, anchored above the pill.
@MainActor
final class IntelligencePanel {
    let model: IntelligencePanelModel
    private let panel: KeyablePanel

    /// Dictation routes here while the panel is key (RoutingSink chain, spec §3).
    var isKey: Bool { panel.isKeyWindow }

    init(session: IntelligenceSession, provisioner: any ModelProvisioning) {
        model = IntelligencePanelModel(session: session, provisioner: provisioner)
        // Tall transparent canvas — the card bottom-aligns inside it and grows upward with
        // content (the old 480×420 clipped the result card's Copy row). Unused area is fully
        // transparent and click-through.
        let canvas = NSRect(x: 0, y: 0, width: 560, height: 760)
        panel = KeyablePanel(contentRect: canvas, styleMask: [.borderless],
                             backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView:
            IntelligenceView(model: model, onClose: { [weak self] in self?.hide() }))
        hosting.frame = canvas
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
    }

    /// Anchor above the pill (bottom-center; the pill canvas is 90 pt tall at minY+24).
    func show(prefillFromClipboard: Bool = false, preselect: IntelligenceChip? = nil) {
        model.reopened(prefillFromClipboard: prefillFromClipboard, preselect: preselect)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                         y: area.minY + 24 + 90 + 12))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel.orderOut(nil) }

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
