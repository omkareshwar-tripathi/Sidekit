import SwiftUI
import SidekitCore

/// The soft-gate sign-up sheet (spec §2): email + honest why, skippable, shown at most
/// twice ever (launch 1, and once more at launch ≥5 — `IdentityStore` owns that rule).
struct WelcomeSheet: View {
    @ObservedObject var identity: IdentityModel
    @Environment(\.dismiss) private var dismiss
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
                Button("Skip for now") { dismiss() }
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
    }

    private func continueTapped() {
        guard identity.submitEmail(email) else { return }
        dismiss()
    }
}
