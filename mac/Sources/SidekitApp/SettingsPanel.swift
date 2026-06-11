import SwiftUI
import AVFoundation
import ApplicationServices
import ServiceManagement
import AppKit
import SidekitCore

/// Observable settings state (spec §2.3): filler-removal (persisted + pushed live to the
/// coordinator), launch-at-login (via `SMAppService`), and read-only mic/Accessibility status.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var fillerRemoval: Bool {
        didSet {
            UserDefaults.standard.set(fillerRemoval, forKey: Self.fillerKey)
            applySettings(SidekitCore.Settings(fillerRemoval: fillerRemoval))
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }
    @Published private(set) var micAuthorized: Bool
    @Published private(set) var accessibilityTrusted: Bool
    /// Shelf retention in seconds; **0 = never expire** (spec §4: 1 day / 2 days / 1 week / never,
    /// default 2 days). Persisted; pushed into the live shelf store, which prunes immediately so a
    /// shortened window takes effect right away.
    @Published var shelfTTLSeconds: Int {
        didSet {
            UserDefaults.standard.set(shelfTTLSeconds, forKey: Self.shelfTTLKey)
            applyShelfTTL(shelfTTLSeconds == 0 ? nil : .seconds(shelfTTLSeconds))
        }
    }
    /// Auto-add macOS screenshots to the Shelf (spec 2026-06-12 §3.3; default ON).
    @Published var autoShelfScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(autoShelfScreenshots, forKey: Self.screenshotsKey)
            applyScreenshotCapture(autoShelfScreenshots)
        }
    }

    private static let fillerKey = "FillerRemoval"
    private static let shelfTTLKey = "ShelfTTL"
    private static let screenshotsKey = "AutoShelfScreenshots"
    /// Pushes a new `Settings` to the live coordinator.
    private let applySettings: @MainActor (SidekitCore.Settings) -> Void
    /// Pushes a new retention TTL (nil = never expire) to the live shelf store.
    private let applyShelfTTL: @MainActor (Duration?) -> Void
    /// Starts/stops the live screenshot watcher.
    private let applyScreenshotCapture: @MainActor (Bool) -> Void

    init(applySettings: @escaping @MainActor (SidekitCore.Settings) -> Void,
         applyShelfTTL: @escaping @MainActor (Duration?) -> Void,
         applyScreenshotCapture: @escaping @MainActor (Bool) -> Void) {
        self.applySettings = applySettings
        self.applyShelfTTL = applyShelfTTL
        self.applyScreenshotCapture = applyScreenshotCapture
        let filler = UserDefaults.standard.object(forKey: Self.fillerKey) as? Bool ?? true
        self.fillerRemoval = filler // init assignment → didSet does not fire
        let ttl = UserDefaults.standard.object(forKey: Self.shelfTTLKey) as? Int ?? 48 * 3600
        self.shelfTTLSeconds = ttl
        let shots = UserDefaults.standard.object(forKey: Self.screenshotsKey) as? Bool ?? true
        self.autoShelfScreenshots = shots // init assignment → didSet does not fire
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.accessibilityTrusted = AXIsProcessTrusted()
        applySettings(SidekitCore.Settings(fillerRemoval: filler)) // seed the coordinator with the saved value
        applyShelfTTL(ttl == 0 ? nil : .seconds(ttl))                // seed the shelf store likewise
        applyScreenshotCapture(shots) // seed: starts the watcher when enabled (default on)
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
    /// The live shelf — drives the store-size readout and Clear all (observed so the size updates).
    @ObservedObject var shelf: ShelfModel
    /// Sign-up email (spec §2: also editable here, any time).
    @ObservedObject var identity: IdentityModel
    @State private var emailDraft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("you@example.com", text: $emailDraft)
                        .onSubmit {
                            // Only act on a real change; a blank Return is a no-op so a
                            // mid-edit Enter can never wipe the signup (review 2026-06-11).
                            let trimmed = emailDraft.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, trimmed.lowercased() != identity.email else { return }
                            identity.submitEmail(emailDraft)
                        }
                    Text(identity.email.map { "Signed up as \($0)" }
                         ?? "Not signed up — add an email to get updates & support.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if identity.email != nil {
                        // Deliberate, explicit removal — local only (spec §2).
                        Button("Remove email", role: .destructive) {
                            identity.clearEmail()
                            emailDraft = ""
                        }
                    }
                }
                Section("Dictation") {
                    Toggle("Remove filler words (um, uh, …)", isOn: $model.fillerRemoval)
                }
                Section("General") {
                    Toggle("Launch Sidekit at login", isOn: $model.launchAtLogin)
                }
                Section("Shelf") {
                    Toggle("Auto-add screenshots to Shelf", isOn: $model.autoShelfScreenshots)
                    Picker("Keep items for", selection: $model.shelfTTLSeconds) {
                        Text("1 day").tag(24 * 3600)
                        Text("2 days").tag(48 * 3600)
                        Text("1 week").tag(7 * 24 * 3600)
                        Text("Never expire").tag(0)
                    }
                    LabeledContent("On disk") {
                        HStack(spacing: DS.Space.sm) {
                            Text(shelfSizeText)
                            if !shelf.isEmpty {
                                Button("Clear all") { shelf.clearAll() }
                            }
                        }
                    }
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
            .onAppear { model.refreshPermissions(); emailDraft = identity.email ?? "" }
        }
        .frame(width: 400, height: 460)
    }

    private var shelfSizeText: String {
        let size = ByteCountFormatter.string(fromByteCount: shelf.totalByteSize, countStyle: .file)
        let count = shelf.items.count
        return "\(count) \(count == 1 ? "item" : "items") · \(size)"
    }

    private func badge(_ ok: Bool) -> some View {
        Label(ok ? "Granted" : "Not granted",
              systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? DS.Palette.success : DS.Palette.recDot)
    }
}
