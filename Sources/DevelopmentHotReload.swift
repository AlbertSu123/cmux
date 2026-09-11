#if DEBUG
import AppKit
import Combine

/// Development-only code injection. No view identity or terminal session is reset.
@MainActor
final class DevelopmentHotReload: ObservableObject {
    static let shared = DevelopmentHotReload()
    @Published private(set) var revision: UInt = 0
    private var observation: AnyCancellable?
    private var compilationObservation: AnyCancellable?
    private var started = false
    private var runtimeHandle: UnsafeMutableRawPointer?

    nonisolated private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    nonisolated private static var runtimePath: String {
        sourceRoot.appendingPathComponent("Packages/macOS/CmuxHotReloadRuntime/.build/debug/libCmuxHotReloadRuntime.dylib").path
    }

    /// Must run before Ghostty initializes its borrowed process-environment snapshot.
    /// The standalone engine only reads these values; it never changes process env.
    nonisolated static func prepareEnvironment() {
        guard isEnabled else { return }
        setenv("INJECTION_DIRECTORIES", sourceRoot.path + "," + NSHomeDirectory() + "/Library/Developer", 1)
        setenv("INJECTION_PRESERVE_STATICS", "1", 1)
    }

    nonisolated private static var isEnabled: Bool {
        NSClassFromString("XCTestCase") == nil &&
        ProcessInfo.processInfo.environment["CMUX_HOT_RELOAD_DISABLED"] != "1" &&
        FileManager.default.fileExists(atPath: runtimePath)
    }

    func start() {
        guard !started else { return }
        started = true
        guard Self.isEnabled else { return }
        observation = NotificationCenter.default.publisher(for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.revision &+= 1
                self.writeStatus("injected")
            }
        compilationObservation = NotificationCenter.default.publisher(for: Notification.Name("CMUX_HOT_RELOAD_COMPILATION"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.writeStatus(notification.userInfo?["state"] as? String ?? "compiling",
                                  error: notification.userInfo?["error"] as? String)
            }
        if let handle = dlopen(Self.runtimePath, RTLD_NOW | RTLD_GLOBAL) {
            runtimeHandle = handle
            if let symbol = dlsym(handle, "cmux_hot_reload_configure") {
                unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)()
            }
            writeStatus("loaded")
        } else {
            writeStatus("load-failed", error: dlerror().map { String(cString: $0) })
        }
    }

    // The live smoke test changes only this function body, then restores it.
    func diagnosticValue() -> String { "cmux-hot-reload-v1" }

    private func writeStatus(_ state: String, error: String? = nil) {
        let pid = ProcessInfo.processInfo.processIdentifier
        var payload: [String: Any] = [
            "pid": pid, "state": state, "revision": revision,
            "probe": diagnosticValue(), "bundleId": Bundle.main.bundleIdentifier ?? "",
        ]
        if let error { payload["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-hot-reload-\(pid).json"), options: .atomic)
        NSLog("cmux hot reload: %@", state)
    }
}
#endif
