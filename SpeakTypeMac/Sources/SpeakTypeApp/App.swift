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
            Text(controller.statusText)
            if !controller.accessibilityTrusted {
                Divider()
                Text("⚠︎ Grant Accessibility to paste & use Fn")
                Button("Open Accessibility Settings…") { controller.openAccessibilitySettings() }
            }
            Divider()
            Button("Quit SpeakType") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: controller.iconName)
        }
    }
}

/// Composition root: builds the adapters, wires them into the `DictationCoordinator`, and
/// drives the menu-bar status. Hold Fn (🌐) to dictate.
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastOutcome: DictationOutcome?
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private let coordinator: DictationCoordinator
    private let hotkey: FnKeyMonitor

    init() {
        let clipboard = MacClipboard()
        let paste = ClipboardSafePaste(clipboard: clipboard)
        let audio = AVAudioCapture()
        let transcriber = WhisperKitTranscriber(modelFolder: Self.bundledModelFolder())
        let coordinator = DictationCoordinator(
            audio: audio,
            transcriber: transcriber,
            sink: PasteSink(paste: paste),
            clock: SystemClock(),
            autoStop: SystemAutoStopTimer()
        )
        let hotkey = FnKeyMonitor()
        self.coordinator = coordinator
        self.hotkey = hotkey

        coordinator.onStateChanged = { [weak self] newState in self?.state = newState }
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
            case .leftOnClipboard: return "Left on clipboard (paste manually)"
            case .noSpeech: return "No speech heard — hold Fn to dictate"
            case nil: return "SpeakType — hold Fn to dictate"
            }
        }
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
