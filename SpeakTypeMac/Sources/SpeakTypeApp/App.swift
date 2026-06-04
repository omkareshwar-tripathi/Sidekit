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
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private let coordinator: DictationCoordinator
    private let hotkey: FnKeyMonitor

    init() {
        let clipboard = MacClipboard()
        let paste = ClipboardSafePaste(clipboard: clipboard)
        let audio = AVAudioCapture()
        let transcriber = StubTranscriber()
        let coordinator = DictationCoordinator(
            audio: audio,
            transcriber: transcriber,
            paste: paste,
            clock: SystemClock(),
            autoStop: SystemAutoStopTimer()
        )
        let hotkey = FnKeyMonitor()
        self.coordinator = coordinator
        self.hotkey = hotkey

        coordinator.onStateChanged = { [weak self] newState in self?.state = newState }
        // NSEvent monitor callbacks arrive on the main thread. press/cancel run
        // synchronously (preserving strict press-before-release ordering); release is async
        // (it awaits transcription), so it hops onto a main-actor Task.
        hotkey.onPressed = { MainActor.assumeIsolated { coordinator.pressed() } }
        hotkey.onReleased = { Task { @MainActor in await coordinator.released() } }
        hotkey.onCancelled = { MainActor.assumeIsolated { coordinator.cancel() } }
        hotkey.start()

        // Prompt for the microphone up front so the first dictation isn't silently empty.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
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
        case .idle: return "SpeakType — hold Fn to dictate"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .pasting: return "Pasting…"
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        accessibilityTrusted = AXIsProcessTrusted()
    }
}
