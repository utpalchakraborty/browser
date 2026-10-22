import ObjectiveC
import os
import WebKit

/// Manual diagnostic for this personal-use browser. WebKit has no public
/// connection-reset API. Keep this private SPI isolated and runtime-checked;
/// it is not suitable for App Store distribution or automatic recovery.
@MainActor
enum WebKitConnectionReset {
    private static let selector = NSSelectorFromString("_terminateNetworkProcess")
    private static let logger = Logger(
        subsystem: "com.utpalchakraborty.browser", category: "NetworkRecovery"
    )
    private typealias ResetFunction = @convention(c) (AnyObject, Selector) -> Void

    static func isSupported(in dataStore: WKWebsiteDataStore) -> Bool {
        resetFunction(in: dataStore) != nil
    }

    @discardableResult
    static func reset(in dataStore: WKWebsiteDataStore) -> Bool {
        guard let reset = resetFunction(in: dataStore) else {
            return false
        }
        // This targets this app's WebKit network process, not system-wide
        // WebKit processes. No website-data deletion or navigation is requested,
        // but WebKit loses in-memory session cookies/storage with this process.
        reset(dataStore, selector)
        logger.notice("Manual WebKit network-process reset requested")
        return true
    }

    private static func resetFunction(in dataStore: WKWebsiteDataStore) -> ResetFunction? {
        guard
            dataStore.responds(to: selector),
            let method = class_getInstanceMethod(type(of: dataStore), selector),
            method_getNumberOfArguments(method) == 2
        else {
            return nil
        }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == "v" else {
            return nil
        }
        // NSObject.perform assumes an object return; this selector returns void.
        return unsafeBitCast(method_getImplementation(method), to: ResetFunction.self)
    }
}
