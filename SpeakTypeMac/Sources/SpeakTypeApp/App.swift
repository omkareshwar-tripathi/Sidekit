import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import SpeakTypeCore

@main
struct SpeakTypeApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.iconName)
        }

        // The main window stays closed until "Open SpeakType" is chosen; opening it flips the
        // app to a Dock-present `.regular` app, closing it returns to the menu-bar-only utility.
        Window("SpeakType", id: MainWindow.id) {
            MainWindow(notes: controller.notes, history: controller.history, settings: controller.settings)
                .onAppear { AppController.setWindowMode(true) }
                .onDisappear { AppController.setWindowMode(false) }
        }
        .windowResizability(.contentSize)
    }
}

/// The menu-bar dropdown. Extracted so it can read `\.openWindow` from the environment to show
/// the main window.
private struct MenuContent: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open SpeakType") { openWindow(id: MainWindow.id) }
        Divider()
        Text(controller.statusText)
        if !controller.accessibilityTrusted {
            Divider()
            Text("⚠︎ Grant Accessibility to paste & use Fn")
            Button("Open Accessibility Settings…") { controller.openAccessibilitySettings() }
        }
        Divider()
        Button("Quit SpeakType") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Composition root: builds the adapters, wires them into the `DictationCoordinator`, and
/// drives the menu-bar status. Hold Fn (🌐) to dictate.
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastOutcome: DictationOutcome?
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    /// Live 0…1 mic level during recording; drives the pill waveform. Resets to 0 when idle.
    @Published private(set) var level: Float = 0

    /// The scratchpad notes (observable wrapper over the pure store). Surfaced to the window and
    /// to the routing sink.
    let notes: NotesModel
    /// The dictation trail (observable wrapper over the pure history store). Surfaced to the window
    /// and recorded into by the history-recording sink.
    let history: HistoryModel
    /// User settings (filler removal, launch-at-login, permission status). Drives the settings sheet.
    let settings: SettingsModel

    private let coordinator: DictationCoordinator
    private let hotkey: FnKeyMonitor
    private var pill: PillPanel?

    init() {
        let clipboard = MacClipboard()
        let paste = ClipboardSafePaste(clipboard: clipboard)
        let audio = AVAudioCapture()
        let transcriber = WhisperKitTranscriber(modelFolder: Self.bundledModelFolder())
        let notes = NotesModel()
        let history = HistoryModel()

        // Route the cleaned transcript: into the active note when SpeakType is the focused app
        // (creating one if the list is empty), otherwise paste at the cursor as before (spec §3).
        // The sink's `deliver` is invoked on the main actor by the coordinator, so the AppKit /
        // notes touches below are safe under `assumeIsolated`.
        let routing = RoutingSink(
            isAppFocused: { MainActor.assumeIsolated { NSApp.isActive } },
            appendToNote: { text in
                MainActor.assumeIsolated {
                    let id = notes.activeID ?? notes.newNote().id
                    notes.append(text, to: id)
                }
            },
            pasteSink: PasteSink(paste: paste))

        // Log every delivered transcript to the dictation trail, then pass the routed outcome
        // through unchanged. Like the routing closures, `record` runs on the main actor.
        let sink = HistoryRecordingSink(inner: routing) { text, outcome in
            MainActor.assumeIsolated { history.record(text, outcome) }
        }

        let coordinator = DictationCoordinator(
            audio: audio,
            transcriber: transcriber,
            sink: sink,
            clock: SystemClock(),
            autoStop: SystemAutoStopTimer()
        )
        let hotkey = FnKeyMonitor()
        // Settings push the persisted filler-removal flag into the live coordinator.
        let settings = SettingsModel(applySettings: { [weak coordinator] s in coordinator?.settings = s })
        self.notes = notes
        self.history = history
        self.settings = settings
        self.coordinator = coordinator
        self.hotkey = hotkey

        audio.onLevel = { [weak self] in self?.level = $0 }
        coordinator.onStateChanged = { [weak self] newState in
            self?.state = newState
            if newState == .recording { self?.lastOutcome = nil } // clear stale "Pasted ✓" when a new hold starts (Brick B)
            if newState != .recording { self?.level = 0 } // settle the waveform once recording ends
        }
        coordinator.onCompleted = { [weak self] outcome in self?.lastOutcome = outcome }
        // NSEvent monitor callbacks arrive on the main thread. press/cancel run
        // synchronously (preserving strict press-before-release ordering); release is async
        // (it awaits transcription), so it hops onto a main-actor Task.
        hotkey.onPressed = { MainActor.assumeIsolated { coordinator.pressed() } }
        hotkey.onReleased = { Task { @MainActor in await coordinator.released() } }
        hotkey.onCancelled = { MainActor.assumeIsolated { coordinator.cancel() } }
        hotkey.start()

        // Prompt for the microphone up front so the first dictation isn't silently empty.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Ask macOS to add this app to Accessibility and prompt the user (needed for the ⌘V
        // paste keystroke and Fn monitoring). Without the prompt option, an un-granted app
        // never appears in the list to toggle. The key's value is the literal below — used
        // directly to avoid Swift 6's concurrency check on the global CFString symbol.
        accessibilityTrusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Diag.log("launch: AXIsProcessTrusted=\(AXIsProcessTrusted()) bundle=\(Bundle.main.bundleURL.path)")

        // Show the always-present floating pill (binds to `self.state`). Created last, once all
        // stored properties are initialized, so it can capture a fully-formed controller.
        pill = PillPanel(controller: self)
    }

    var iconName: String {
        switch state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .pasting: return "doc.on.clipboard"
        }
    }

    var statusText: String {
        switch state {
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .pasting: return "Pasting…"
        case .idle:
            switch lastOutcome {
            case .pasted: return "Pasted ✓ — hold Fn to dictate"
            case .addedToNote: return "Added to note ✓ — hold Fn to dictate"
            case .leftOnClipboard: return "Copied to clipboard — ⌘V to paste"
            case .noSpeech: return "No speech heard — hold Fn to dictate"
            case nil: return "SpeakType — hold Fn to dictate"
            }
        }
    }

    /// Switch activation policy (spec §7): `.regular` (Dock icon, ⌘-Tab, can take focus) while the
    /// main window is open; `.accessory` (pure menu-bar background utility) when it closes. The
    /// floating pill is a non-activating panel and never triggers this.
    static func setWindowMode(_ open: Bool) {
        NSApp.setActivationPolicy(open ? .regular : .accessory)
        if open { NSApp.activate(ignoringOtherApps: true) }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        accessibilityTrusted = AXIsProcessTrusted()
    }

    /// The model bundled into the app (`Resources/Models/openai_whisper-base.en`), or nil if
    /// absent (a plain `swift run` without `build-app.sh`) — then the transcriber falls back
    /// to downloading.
    static func bundledModelFolder() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let folder = resources.appendingPathComponent("Models/openai_whisper-base.en")
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }
}
