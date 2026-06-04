import SwiftUI
import AppKit

// MAC-1 shell: a menu-bar-only app (no Dock icon — see LSUIElement in Info.plist).
// The real dictation wiring (coordinator + adapters) lands in MAC-2…MAC-6; this brick
// just proves the SwiftUI MenuBarExtra app builds, bundles, and runs.
@main
struct SpeakTypeApp: App {
    var body: some Scene {
        MenuBarExtra("SpeakType", systemImage: "mic.fill") {
            Text("SpeakType")
            Divider()
            Button("Quit SpeakType") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
