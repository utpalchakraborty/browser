import AppKit
import WebKit

@MainActor
final class BrowserWebView: WKWebView {
    var onOpenSelectedURL: ((URL) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard onOpenSelectedURL != nil,
              let selection = selectedText(),
              let url = AddressInterpreter.selectedWebURL(from: selection)
        else {
            return
        }

        let item = NSMenuItem(
            title: "Open Selected URL in New Tab",
            action: #selector(openSelectedURLInNewTab(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = url
        item.toolTip = url.absoluteString
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(item, at: 0)
    }

    private func selectedText() -> String? {
        // Use WebKit's native Services selection, including editable fields and
        // subframes. A unique pasteboard leaves the user's clipboard untouched.
        // WebKit's Services implementation requires AppKit's legacy string type.
        let stringType = NSPasteboard.PasteboardType("NSStringPboardType")
        guard let requestor = validRequestor(
            forSendType: stringType, returnType: nil
        ) as AnyObject?, requestor === self else {
            return nil
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        // NSServicesMenuRequestor is an informal Objective-C protocol; WebKit
        // implements its optional method without declaring Swift conformance.
        guard requestor.writeSelection?(to: pasteboard, types: [stringType]) == true else {
            return nil
        }
        return pasteboard.string(forType: stringType)
    }

    @objc private func openSelectedURLInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        onOpenSelectedURL?(url)
    }
}
