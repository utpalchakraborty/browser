import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let maximumPerformanceViewCount = 10

    private lazy var profile = BrowserProfile(
        dataStoreIdentifier: BrowserProfile.applicationDataStoreIdentifier(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    )
    private var browserWindowController: BrowserWindowController?
#if DEBUG
    private var profilePersistenceProbe: ProfilePersistenceProbe?
#endif

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if startProfilePersistenceProbeIfRequested() {
            return
        }
#endif

        NSApp.setActivationPolicy(.regular)
        NSApp.disableRelaunchOnLogin()
        installMainMenu()

        let presentationState = BrowserPerformanceSignposts.signposter.beginInterval(
            "InitialWindowPresentation"
        )
        let controller = BrowserWindowController()
        browserWindowController = controller
        controller.showWindow(nil)
        NSApp.activate()
        controller.window?.displayIfNeeded()
        BrowserPerformanceSignposts.signposter.endInterval(
            "InitialWindowPresentation",
            presentationState
        )

        // Give AppKit one run-loop turn to present responsive native chrome
        // before WebKit starts its heavier process and data-store setup.
        DispatchQueue.main.async { [weak self, weak controller] in
            guard
                let self,
                let controller,
                self.browserWindowController === controller,
                controller.window?.isVisible == true
            else {
                return
            }
            controller.startWebViews(
                profile: self.profile,
                viewCount: Self.performanceViewCount(
                    arguments: ProcessInfo.processInfo.arguments
                ),
                initialURL: Self.performanceFixtureURL(
                    arguments: ProcessInfo.processInfo.arguments
                ) ?? URL(string: "about:blank")!
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    static func performanceViewCount(arguments: [String]) -> Int {
        guard
            arguments.contains("--performance-test"),
            let optionIndex = arguments.firstIndex(
                of: "--performance-view-count"
            ),
            arguments.indices.contains(optionIndex + 1),
            let count = Int(arguments[optionIndex + 1]),
            (1...maximumPerformanceViewCount).contains(count)
        else {
            return 1
        }
        return count
    }

    static func performanceFixtureURL(arguments: [String]) -> URL? {
        guard
            arguments.contains("--performance-test"),
            let optionIndex = arguments.firstIndex(
                of: "--performance-fixture-url"
            ),
            arguments.indices.contains(optionIndex + 1),
            let url = URL(string: arguments[optionIndex + 1]),
            url.scheme == "http",
            let host = url.host?.lowercased(),
            ["127.0.0.1", "localhost"].contains(host),
            url.user == nil,
            url.password == nil
        else {
            return nil
        }
        return url
    }

#if DEBUG
    private func startProfilePersistenceProbeIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard ProfilePersistenceProbe.isRequested(arguments: arguments) else {
            return false
        }
        guard let configuration = ProfilePersistenceProbe.configuration(
            arguments: arguments
        ) else {
            ProfilePersistenceProbe.emitInvalidConfiguration()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return true
        }

        let probe = ProfilePersistenceProbe(configuration: configuration)
        profilePersistenceProbe = probe
        Task { [weak self, probe] in
            let result = await probe.run()
            ProfilePersistenceProbe.emit(result)
            self?.profilePersistenceProbe = nil
            NSApp.terminate(nil)
        }
        return true
    }
#endif

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)

        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "Quit Browser",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu
        NSApp.mainMenu = mainMenu
    }
}
