import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import SpeakTypeCore

/// Posted when the app should bring its main window forward — on launch and whenever the user
/// re-activates the app (clicks it in Launchpad / Finder / Dock). `MenuBarLabel` (always alive in
/// the menu bar) listens and calls `openWindow`.
extension Notification.Name {
    static let openMainWindow = Notification.Name("SpeakTypeOpenMainWindow")
}

/// Bridges AppKit re-open events to the SwiftUI window. A menu-bar-only (`LSUIElement`) app doesn't
/// auto-open its `Window` scene, so clicking the app icon while it's already running would otherwise
/// do nothing visible — this re-opens (or focuses) the main window. (The first launch is handled by
/// `MenuBarLabel.onAppear`, which is race-free.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }
}

@main
struct SpeakTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }

        // The main window stays closed until "Open Sidekit" is chosen; opening it flips the
        // app to a Dock-present `.regular` app, closing it returns to the menu-bar-only utility.
        Window("Sidekit", id: MainWindow.id) {
            MainWindow(notes: controller.notes, history: controller.history,
                       settings: controller.settings, shelf: controller.shelf)
                .onAppear { AppController.setWindowMode(true) }
                .onDisappear { AppController.setWindowMode(false) }
        }
        .windowResizability(.contentSize)
    }
}

/// The menu-bar icon. Idle shows the static SpeakType equalizer; recording shows the **live**
/// equalizer (bars driven by the mic level); the other active states keep their SF Symbols so
/// status stays legible. Also the home for the `openMainWindow` listener — it's always alive in
/// the menu bar, so it can open the window on launch / re-click via `\.openWindow`.
private struct MenuBarLabel: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    /// Guards the launch open so it happens exactly once (the label can re-appear when the app
    /// flips activation policy as the window opens/closes).
    @State private var openedAtLaunch = false

    var body: some View {
        icon
            // Opening from `.onAppear` (rather than a launch notification) is race-free: the label
            // — and its `openWindow` action — are guaranteed live by the time this runs.
            .onAppear {
                guard !openedAtLaunch else { return }
                openedAtLaunch = true
                // Skip the auto-open when launch-at-login is enabled: macOS may have started the
                // app at login, and a quiet menu-bar utility shouldn't pop its window every login.
                // A manual click while it's running still opens it (applicationShouldHandleReopen).
                if SMAppService.mainApp.status != .enabled { showWindow() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in showWindow() }
    }

    private func showWindow() {
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder private var icon: some View {
        if controller.state == .recording, let wave = controller.recordingMenuIcon {
            Image(nsImage: wave)
        } else if controller.state == .idle, let idle = controller.menuBarIcon {
            Image(nsImage: idle)
        } else {
            Image(systemName: controller.iconName)
        }
    }
}

/// The menu-bar dropdown. Extracted so it can read `\.openWindow` from the environment to show
/// the main window.
private struct MenuContent: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Sidekit") { openWindow(id: MainWindow.id) }
        Divider()
        Text(controller.statusText)
        if !controller.accessibilityTrusted {
            Divider()
            Text("⚠︎ Grant Accessibility to paste & use Fn")
            Button("Open Accessibility Settings…") { controller.openAccessibilitySettings() }
        }
        Divider()
        Button("Quit Sidekit") { NSApplication.shared.terminate(nil) }
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
    /// The live menu-bar waveform image while recording (bars driven by `level`); nil otherwise,
    /// so the label falls back to the static idle glyph / SF Symbols.
    @Published private(set) var recordingMenuIcon: NSImage?
    /// Advances each mic-level frame to animate the menu waveform's per-bar wobble.
    private var wavePhase = 0.0

    /// The scratchpad notes (observable wrapper over the pure store). Surfaced to the window and
    /// to the routing sink.
    let notes: NotesModel
    /// The dictation trail (observable wrapper over the pure history store). Surfaced to the window
    /// and recorded into by the history-recording sink.
    let history: HistoryModel
    /// User settings (filler removal, launch-at-login, permission status). Drives the settings sheet.
    let settings: SettingsModel
    /// The Shelf (observable wrapper over the pure store). Surfaced to the summoned `ShelfPanel`.
    let shelf: ShelfModel
    /// Custom menu-bar glyph (mic + waveform) shown in the idle state. nil when running un-bundled
    /// (plain `swift run`) — the label then falls back to the "mic" SF Symbol.
    let menuBarIcon: NSImage? = AppController.loadMenuBarIcon()

    private let coordinator: DictationCoordinator
    private let hotkey: FnKeyMonitor
    private var pill: PillPanel?
    private var shelfPanel: ShelfPanel?
    private var shelfStatusItem: ShelfStatusItem?
    private var shelfDragMonitor: ShelfDragStartMonitor?
    /// Hourly expiry sweep (spec §4) — lives as long as the controller (the whole app).
    private var shelfPruneTask: Task<Void, Never>?

    init() {
        let clipboard = MacClipboard()
        let paste = ClipboardSafePaste(clipboard: clipboard)
        let audio = AVAudioCapture()
        let transcriber = WhisperKitTranscriber(modelFolder: Self.bundledModelFolder())
        let notes = NotesModel()
        let history = HistoryModel()
        let shelf = ShelfModel()

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
        // Settings push the persisted filler-removal flag into the live coordinator, and the
        // persisted shelf TTL into the live shelf store (both seeded at init with saved values).
        let settings = SettingsModel(
            applySettings: { [weak coordinator] s in coordinator?.settings = s },
            applyShelfTTL: { ttl in shelf.setRetentionTTL(ttl) })
        self.notes = notes
        self.history = history
        self.settings = settings
        self.shelf = shelf
        self.coordinator = coordinator
        self.hotkey = hotkey

        audio.onLevel = { [weak self] lvl in
            guard let self else { return }
            self.level = lvl
            // Render the next live-waveform frame for the menu bar while recording.
            if self.state == .recording {
                self.wavePhase += 0.55
                self.recordingMenuIcon = MenuBarWave.icon(level: CGFloat(lvl), phase: self.wavePhase)
            }
        }
        coordinator.onStateChanged = { [weak self] newState in
            self?.state = newState
            if newState == .recording { self?.lastOutcome = nil } // clear stale "Pasted ✓" when a new hold starts (Brick B)
            if newState != .recording {
                self?.level = 0              // settle the waveform once recording ends
                self?.recordingMenuIcon = nil // menu glyph returns to the static idle equalizer
            }
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
        // The Shelf panel starts hidden; a dedicated menu-bar icon click toggles it.
        shelfPanel = ShelfPanel(
            model: shelf,
            onClose: { [weak self] in self?.shelfPanel?.hide() })
        shelfStatusItem = ShelfStatusItem(
            onClick: { [weak self] in
                self?.shelf.prune() // expired items must never appear on summon
                self?.shelfPanel?.toggle()
            })
        // Auto-summon the Shelf at the cursor when a file drag starts anywhere on the system, and
        // let it slip away when the drag ends elsewhere (spec decision #4). Monitor callbacks arrive
        // on the main thread (same pattern as the hotkey above).
        let shelfDragMonitor = ShelfDragStartMonitor()
        shelfDragMonitor.onFileDragStart = { [weak self] in
            MainActor.assumeIsolated {
                self?.shelf.prune()
                self?.shelfPanel?.showForDrag()
            }
        }
        shelfDragMonitor.onDragEnd = { [weak self] in
            MainActor.assumeIsolated { self?.shelfPanel?.dragEnded() }
        }
        shelfDragMonitor.start()
        self.shelfDragMonitor = shelfDragMonitor
        // Spec §4: expiry also runs on a periodic timer, so the TTL holds (and the payload bytes are
        // actually deleted) even while the app idles in the menu bar for days. The Task inherits the
        // main actor, so the hourly prune touches the model safely.
        shelfPruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.shelf.prune()
            }
        }
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

    /// Loads the bundled menu-bar template glyph (`Resources/MenuBarIcon.pdf`), sized for the menu
    /// bar and marked as a template so macOS tints it for light/dark. nil if absent (un-bundled run).
    static func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        return image
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
