import AppKit

/// A dedicated menu-bar icon for the Shelf, separate from the SpeakType `MenuBarExtra`. One click
/// toggles the floating Shelf panel directly (no dropdown). An `NSStatusItem` is used rather than a
/// second `MenuBarExtra` because the latter opens its own menu/window — we want a plain click action.
///
/// `NSObject` so it can be the button's target/action; held strongly by `AppController` so the
/// status item stays in the menu bar for the app's lifetime.
@MainActor
final class ShelfStatusItem: NSObject {
    private let item: NSStatusItem
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Shelf")
            image?.isTemplate = true // tints to match the menu bar (light/dark)
            button.image = image
            button.toolTip = "Shelf"
            button.target = self
            button.action = #selector(clicked)
        }
    }

    @objc private func clicked() { onClick() }
}
