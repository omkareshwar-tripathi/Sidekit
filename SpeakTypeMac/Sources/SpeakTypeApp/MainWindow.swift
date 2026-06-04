import SwiftUI

/// The app's main window. UI-4 establishes it as a window-capable surface (activation-policy
/// switching lives in `AppController.setWindowMode`); the sidebar + editor scratchpad content
/// lands in UI-8. For now it previews the glass design system so the look can be eyeballed.
struct MainWindow: View {
    static let id = "main"

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            Text("SpeakType")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("Scratchpad coming soon")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .padding(DS.Space.lg)
        .frame(width: 360, height: 220)
        .glassCard()
        .padding(DS.Space.lg)
        .background(DS.accentGradient.opacity(0.2).ignoresSafeArea())
    }
}
