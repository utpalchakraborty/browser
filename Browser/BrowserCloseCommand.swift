import AppKit

/// Resolve ownership at dispatch time, so an auxiliary key window can never
/// close a tab in the browser behind it.
@MainActor
final class BrowserCloseCommand: NSObject, NSMenuItemValidation {
    private weak var browser: BrowserWindowController?
    private let keyWindow: () -> NSWindow?

    init(browser: BrowserWindowController, keyWindow: @escaping () -> NSWindow? = { NSApp.keyWindow }) {
        self.browser = browser
        self.keyWindow = keyWindow
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Close", action: #selector(closeCurrentContent(_:)), keyEquivalent: "w")
        item.keyEquivalentModifierMask = .command
        item.target = self
        return item
    }

    @objc
    func closeCurrentContent(_ sender: Any?) {
        guard let window = closableKeyWindow else { return }
        if window === browser?.window {
            browser?.closeSelectedTab(sender)
        } else {
            window.performClose(sender)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let window = closableKeyWindow else {
            menuItem.title = "Close"
            return false
        }
        menuItem.title = window === browser?.window ? "Close Tab" : "Close Window"
        return true
    }

    private var closableKeyWindow: NSWindow? {
        guard let window = keyWindow(),
              window.sheetParent == nil,
              window.attachedSheet == nil,
              window.styleMask.contains(.closable) else { return nil }
        return window
    }
}
