import SwiftUI
import SpeakTypeCore

/// The four visual states of the floating pill, derived from the coordinator's `DictationState`
/// plus the last outcome. UI-5 renders them statically; UI-6 feeds a live waveform level and
/// UI-7 adds the spring morphs + the ~1.2 s success-then-collapse timing.
enum PillState {
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
                self = .done(symbol: "doc.on.clipboard", tint: DS.Palette.textSecondary, label: "On clipboard")
            case .noSpeech:
                self = .done(symbol: "mic.slash", tint: DS.Palette.textSecondary, label: "No speech")
            case nil:
                self = .idle
            }
        }
    }
}

/// The pill itself. Idle is a bare, dim bar (auto-dimmed background utility); the active states
/// expand into a frosted-glass capsule. Bound to `AppController`, so it re-renders on state change.
struct PillView: View {
    @ObservedObject var controller: AppController

    private var pill: PillState { PillState(state: controller.state, outcome: controller.lastOutcome) }

    var body: some View {
        switch pill {
        case .idle:
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 28, height: 5)
        case .recording:
            glassPill(label: "Listening…") {
                HStack(spacing: DS.Space.sm) {
                    Circle().fill(DS.Palette.recDot).frame(width: 8, height: 8)
                    WaveformBars(level: CGFloat(controller.level))
                }
            }
        case .transcribing:
            glassPill(label: "Transcribing…") {
                Image(systemName: "waveform").foregroundStyle(DS.Palette.accent)
            }
        case let .done(symbol, tint, label):
            glassPill(label: label) {
                Image(systemName: symbol).foregroundStyle(tint)
            }
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
/// level scales them together (with a small floor so the bars stay visible at silence). Per-bar
/// smoothing/animation is UI-7.
private struct WaveformBars: View {
    var level: CGFloat
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
    }
}
