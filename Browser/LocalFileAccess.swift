import AppKit
import Foundation

nonisolated struct LocalFileAuthorization: Equatable, Sendable {
    let fileURL: URL
    let readAccessURL: URL
    let securityScopedURL: URL
}

nonisolated enum LocalFileAccessPolicy {
    private static let supportedPathExtensions: Set<String> = [
        "htm",
        "html",
    ]

    static func isLocalFileURL(_ url: URL) -> Bool {
        guard
            url.isFileURL,
            url.path.hasPrefix("/"),
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            components.user == nil,
            components.password == nil,
            components.port == nil
        else {
            return false
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else {
            return true
        }
        return host == "localhost"
    }

    static func isSupportedHTMLFile(_ url: URL) -> Bool {
        isLocalFileURL(url)
            && !url.hasDirectoryPath
            && supportedPathExtensions.contains(
                url.pathExtension.lowercased()
            )
    }

    static func standardizedNavigationURL(_ url: URL) -> URL? {
        guard isLocalFileURL(url) else {
            return nil
        }
        return navigationURL(
            at: url.standardizedFileURL,
            preservingComponentsFrom: url
        )
    }

    static func resolvedNavigationURL(_ url: URL) -> URL? {
        guard isLocalFileURL(url) else {
            return nil
        }
        return navigationURL(
            at: resolvedURL(url),
            preservingComponentsFrom: url
        )
    }

    static func authorization(
        for fileURL: URL,
        selectedDirectoryURL: URL
    ) -> LocalFileAuthorization? {
        guard
            isSupportedHTMLFile(fileURL),
            isLocalFileURL(selectedDirectoryURL)
        else {
            return nil
        }

        let resolvedFileURL = resolvedURL(fileURL)
        let resolvedDirectoryURL = resolvedURL(selectedDirectoryURL)
        guard
            resolvedFileURL.deletingLastPathComponent()
                == resolvedDirectoryURL,
            contains(resolvedFileURL, in: resolvedDirectoryURL),
            (try? resolvedFileURL.resourceValues(
                forKeys: [.isRegularFileKey]
            ).isRegularFile) == true,
            (try? resolvedDirectoryURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) == true
        else {
            return nil
        }

        return LocalFileAuthorization(
            fileURL: navigationURL(
                at: resolvedFileURL,
                preservingComponentsFrom: fileURL
            ),
            readAccessURL: resolvedDirectoryURL,
            securityScopedURL: selectedDirectoryURL
        )
    }

    static func contains(_ fileURL: URL, in directoryURL: URL) -> Bool {
        guard
            isLocalFileURL(fileURL),
            isLocalFileURL(directoryURL)
        else {
            return false
        }

        let fileComponents = resolvedURL(fileURL).pathComponents
        let directoryComponents = resolvedURL(directoryURL).pathComponents
        guard fileComponents.count > directoryComponents.count else {
            return false
        }
        return fileComponents.prefix(directoryComponents.count)
            .elementsEqual(directoryComponents)
    }

    static func refersToSameFile(_ firstURL: URL?, _ secondURL: URL?) -> Bool {
        guard
            let firstURL,
            let secondURL,
            isLocalFileURL(firstURL),
            isLocalFileURL(secondURL)
        else {
            return false
        }
        return resolvedURL(firstURL).path
            == resolvedURL(secondURL).path
    }

    private static func resolvedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func navigationURL(
        at fileURL: URL,
        preservingComponentsFrom originalURL: URL
    ) -> URL {
        guard
            let originalComponents = URLComponents(
                url: originalURL,
                resolvingAgainstBaseURL: false
            ),
            var resolvedComponents = URLComponents(
                url: fileURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return fileURL
        }
        resolvedComponents.percentEncodedQuery = normalizedComponent(
            originalComponents.percentEncodedQuery
        )
        resolvedComponents.percentEncodedFragment = normalizedComponent(
            originalComponents.percentEncodedFragment
        )
        return resolvedComponents.url ?? fileURL
    }

    private static func normalizedComponent(_ component: String?) -> String? {
        component?.isEmpty == true ? nil : component
    }
}

nonisolated enum LocalFileNavigationPolicy {
    static func allows(
        targetURL: URL?,
        sourceURL: URL?,
        readAccessURL: URL?,
        approvedURL: URL?,
        isMainFrame: Bool,
        isBackForwardNavigation: Bool
    ) -> Bool {
        guard
            let targetURL,
            let readAccessURL,
            LocalFileAccessPolicy.isSupportedHTMLFile(targetURL),
            LocalFileAccessPolicy.contains(targetURL, in: readAccessURL)
        else {
            return false
        }

        if
            isMainFrame,
            LocalFileAccessPolicy.refersToSameFile(targetURL, approvedURL)
        {
            return true
        }
        if
            let sourceURL,
            LocalFileAccessPolicy.isLocalFileURL(sourceURL),
            LocalFileAccessPolicy.contains(sourceURL, in: readAccessURL)
        {
            return true
        }
        return isMainFrame && isBackForwardNavigation
    }
}

@MainActor
protocol LocalFileAccessAuthorizing: AnyObject {
    func requestAccess(
        toContainingDirectoryOf fileURL: URL,
        from window: NSWindow,
        completion: @escaping @MainActor (URL?) -> Void
    )

    func cancel()
}

@MainActor
final class OpenPanelLocalFileAccessAuthorizer: LocalFileAccessAuthorizing {
    private var panel: NSOpenPanel?

    func requestAccess(
        toContainingDirectoryOf fileURL: URL,
        from window: NSWindow,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        cancel()

        let containingDirectory = fileURL.standardizedFileURL
            .deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.title = "Allow Local Page Folder"
        panel.message = "Approve this HTML file’s folder so Browser can read its local images, scripts, and styles."
        panel.prompt = "Allow Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.directoryURL = containingDirectory
        self.panel = panel

        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let panel else {
                completion(nil)
                return
            }
            if self?.panel === panel {
                self?.panel = nil
            }
            completion(response == .OK ? panel.url : nil)
        }
    }

    func cancel() {
        panel?.cancel(nil)
        panel = nil
    }
}
