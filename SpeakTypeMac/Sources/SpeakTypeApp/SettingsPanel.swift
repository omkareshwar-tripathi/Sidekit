import SwiftUI
import AVFoundation
import ApplicationServices
import ServiceManagement
import AppKit
import SpeakTypeCore

/// Observable settings state (spec §2.3): filler-removal (persisted + pushed live to the
/// coordinator), launch-at-login (via `SMAppService`), and read-only mic/Accessibility status.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var fillerRemoval: Bool {
        didSet {
            UserDefaults.standard.set(fillerRemoval, forKey: Self.fillerKey)
            applySettings(SpeakTypeCore.Settings(fillerRemoval: fillerRemoval))
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }
    @Published private(set) var micAuthorized: Bool
    @Published private(set) var accessibilityTrusted: Bool

    private static let fillerKey = "FillerRemoval"
    /// Pushes a new `Settings` to the live coordinator.
    private let applySettings: @MainActor (SpeakTypeCore.Settings) -> Void

    init(applySettings: @escaping @MainActor (SpeakTypeCore.Settings) -> Void) {
        self.applySettings = applySettings
        let filler = UserDefaults.standard.object(forKey: Self.fillerKey) as? Bool ?? true
        self.fillerRemoval = filler // init assignment → didSet does not fire
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.accessibilityTrusted = AXIsProcessTrusted()
        applySettings(SpeakTypeCore.Settings(fillerRemoval: filler)) // seed the coordinator with the saved value
    }

    /// Re-read the OS permission state (the user may have changed it in System Settings).
    func refreshPermissions() {
        micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Diag.log("launch-at-login: \(error)")
        }
    }
}

/// The settings sheet shown from the window's ⚙︎ button.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Dictation") {
                    Toggle("Remove filler words (um, uh, …)", isOn: $model.fillerRemoval)
                }
                Section("General") {
                    Toggle("Launch SpeakType at login", isOn: $model.launchAtLogin)
                }
                Section("Permissions") {
                    LabeledContent("Microphone") { badge(model.micAuthorized) }
                    LabeledContent("Accessibility") {
                        HStack(spacing: DS.Space.sm) {
                            badge(model.accessibilityTrusted)
                            if !model.accessibilityTrusted {
                                Button("Open Settings…") { model.openAccessibilitySettings() }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { model.refreshPermissions() }
        }
        .frame(width: 400, height: 380)
    }

    private func badge(_ ok: Bool) -> some View {
        Label(ok ? "Granted" : "Not granted",
              systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? DS.Palette.success : DS.Palette.recDot)
    }
}
