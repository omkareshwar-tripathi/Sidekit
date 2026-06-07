import SwiftUI
import SpeakTypeCore

/// The four visual states of the floating pill, derived from the coordinator's `DictationState`
/// plus the last outcome. `Equatable` so SwiftUI can animate morphs between them.
enum PillState: Equatable {
    case idle
    case recording
    case transcribing
    case done(symbol: String, tint: Color, label: String)

    init(state: DictationState, outcome: DictationOutcome?) {
        switch state {
        case .recording:
            self = .recording
        case .transcribing, .pasting:
            self = .transcribing
        case .idle:
            switch outcome {
            case .pasted:
                self = .done(symbol: "checkmark.circle.fill", tint: DS.Palette.success, label: "Pasted")
            case .addedToNote:
                self = .done(symbol: "checkmark.circle.fill", tint: DS.Palette.success, label: "Added to note")
            case .leftOnClipboard:
                self = .done(symbol: "doc.on.clipboard", tint: DS.Palette.textSecondary, label: "Copied to clipboard")
            case .noSpeech:
                self = .done(symbol: "mic.slash", tint: DS.Palette.textSecondary, label: "No speech")
            case nil:
                self = .idle
            }
        }
    }
}

/// The pill. Idle is a faint, slowly-breathing bar; the active states spring open into a frosted
/// glass capsule; the success state pops, holds ~1.2 s, then collapses back to the idle bar.
/// Under Reduce Motion, every spring/morph degrades to a plain opacity fade (feedback is never
/// removed, only de-animated — spec §9).
struct PillView: View {
    @ObservedObject var controller: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while a finished outcome is held on screen; flips false ~1.2 s later to collapse the
    /// success pill back to the idle bar.
    @State private var showSuccess = false
    @State private var breathing = false
    @State private var collapseTask: Task<Void, Never>?

    /// The state to render: the raw state, except a finished outcome whose hold has elapsed reads
    /// as idle (so the pill returns to the dot rather than parking on "Pasted ✓").
    private var pill: PillState {
        let raw = PillState(state: controller.state, outcome: controller.lastOutcome)
        if case .done = raw, !showSuccess { return .idle }
        return raw
    }

    var body: some View {
        content
            .animation(morph, value: pill)
            .onChange(of: controller.state) { _, newState in handleStateChange(newState) }
            .onAppear { if !reduceMotion { breathing = true } }
    }

    @ViewBuilder private var content: some View {
        switch pill {
        case .idle:
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 28, height: 5)
                .scaleEffect(breathing ? 1.0 : 0.85)
                .opacity(breathing ? 0.55 : 0.3)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: breathing)
        case .recording:
            glassPill(label: "Listening…") {
                HStack(spacing: DS.Space.sm) {
                    Circle().fill(DS.Palette.recDot).frame(width: 8, height: 8)
                    WaveformBars(level: CGFloat(controller.level), reduceMotion: reduceMotion)
                }
            }
            .transition(.scale.combined(with: .opacity))
        case .transcribing:
            glassPill(label: "Transcribing…") {
                ProgressView().controlSize(.small).tint(DS.Palette.accent)
            }
            .transition(.opacity)
        case let .done(symbol, tint, label):
            glassPill(label: label) {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    /// Spring for the lively look; a quick fade when Reduce Motion is on.
    private var morph: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.72)
    }

    /// Drive the success hold/collapse off coordinator state transitions.
    private func handleStateChange(_ newState: DictationState) {
        collapseTask?.cancel()
        switch newState {
        case .recording:
            showSuccess = false // a fresh cycle clears any lingering outcome
        case .idle where controller.lastOutcome != nil:
            showSuccess = true
            collapseTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { showSuccess = false }
            }
        default:
            break
        }
    }

    private func glassPill(label: String, @ViewBuilder leading: () -> some View) -> some View {
        HStack(spacing: DS.Space.sm) {
            leading()
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .glassCard(cornerRadius: DS.Radius.pill)
    }
}

/// Waveform bars driven by the live 0…1 mic `level`. Each bar has a fixed silhouette weight; the
/// level scales them together (0.2 floor so the bars stay visible at silence). Height changes
/// glide via a short ease-out unless Reduce Motion is on.
private struct WaveformBars: View {
    var level: CGFloat
    var reduceMotion: Bool
    private let shape: [CGFloat] = [0.4, 0.75, 0.55, 1.0, 0.5, 0.8, 0.45]
    private let maxBar: CGFloat = 18

    var body: some View {
        HStack(spacing: 2) {
            ForEach(shape.indices, id: \.self) { i in
                Capsule()
                    .fill(DS.accentGradient)
                    .frame(width: 2.5, height: max(3, maxBar * shape[i] * (0.2 + 0.8 * level)))
            }
        }
        .frame(height: maxBar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    }
}
