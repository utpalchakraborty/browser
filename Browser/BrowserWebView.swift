import AppKit
import WebKit

@MainActor
final class BrowserWebView: WKWebView {
    var onOpenSelectedURL: ((URL) -> Void)?
    var onOpenLinkInNewTab: ((URL) -> Void)?

    // WebKit's stock items for new windows and downloads. Browser denies
    // page-created windows and has no downloads yet, so they would do nothing.
    private static let openLinkInNewWindowIdentifier =
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLinkInNewWindow")
    private static let unsupportedMenuItemIdentifiers: Set<NSUserInterfaceItemIdentifier> = [
        openLinkInNewWindowIdentifier,
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenImageInNewWindow"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenFrameInNewWindow"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenMediaInNewWindow"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadLinkedFile"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadImage"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadMedia"),
    ]
    static let openLinkInNewTabIdentifier =
        NSUserInterfaceItemIdentifier("BrowserOpenLinkInNewTab")

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let linkItemIndex = menu.items.firstIndex {
            $0.identifier == Self.openLinkInNewWindowIdentifier
        }
        for item in menu.items where item.identifier.map(Self.unsupportedMenuItemIdentifiers.contains) == true {
            menu.removeItem(item)
        }
        if let linkItemIndex, onOpenLinkInNewTab != nil {
            let item = NSMenuItem(
                title: "Open Link in New Tab",
                action: #selector(openLinkInNewTab(_:)),
                keyEquivalent: ""
            )
            item.identifier = Self.openLinkInNewTabIdentifier
            item.target = self
            // The URL arrives asynchronously; the item is removed if none resolves.
            menu.insertItem(item, at: min(linkItemIndex, menu.items.count))
            resolveLink(at: convert(event.locationInWindow, from: nil), for: item, in: menu)
        }
        Self.removeRedundantSeparators(from: menu)

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

    /// Finds the link under the context-menu point. The script runs in WebKit's
    /// isolated client world, so page scripts cannot replace the DOM methods it uses.
    private func resolveLink(at point: NSPoint, for item: NSMenuItem, in menu: NSMenu) {
        // CSS viewport coordinates; Browser never enables pinch magnification.
        let scale = max(pageZoom, 0.01)
        let viewportPoint = NSPoint(
            x: point.x / scale,
            y: (isFlipped ? point.y : bounds.height - point.y) / scale
        )
        Task { [weak self, weak item, weak menu] in
            let result = try? await self?.callAsyncJavaScript(
                """
                const element = document.elementFromPoint(x, y);
                const link = element && element.closest('a[href], area[href]');
                return link ? link.href : null;
                """,
                arguments: ["x": viewportPoint.x, "y": viewportPoint.y],
                in: nil,
                contentWorld: .defaultClient
            )
            guard let item else {
                return
            }
            guard
                let string = result as? String,
                let url = URL(string: string),
                ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else {
                if let menu, menu.items.contains(item) {
                    menu.removeItem(item)
                    Self.removeRedundantSeparators(from: menu)
                }
                return
            }
            item.representedObject = url
            item.toolTip = url.absoluteString
        }
    }

    private static func removeRedundantSeparators(from menu: NSMenu) {
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem, previousWasSeparator {
                menu.removeItem(item)
            } else {
                previousWasSeparator = item.isSeparatorItem
            }
        }
        if let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
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

    @objc private func openLinkInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        onOpenLinkInNewTab?(url)
    }
}
