import Foundation
import InjectionLite

// The pinned upstream boot hook skips implicit startup when this Objective-C
// class exists. Own startup so build-log discovery finishes before the watcher.
@objc(InjectionNext)
private final class ExplicitRuntimeStartup: NSObject {}
private var engine: InjectionLite?

private func matchingBuildLog(sourceRoot: String) -> URL? {
    let manager = FileManager.default
    let derivedData = manager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Xcode/DerivedData")
    let builds = (try? manager.contentsOfDirectory(at: derivedData, includingPropertiesForKeys: nil)) ?? []
    let matching = builds.filter { build in
        guard let data = try? Data(contentsOf: build.appendingPathComponent("info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let workspace = info["WorkspacePath"] as? String else { return false }
        return workspace.hasPrefix(sourceRoot + "/")
    }
    let logs = matching.flatMap { build in
        (try? manager.contentsOfDirectory(at: build.appendingPathComponent("Logs/Build"),
                                          includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }.filter { $0.pathExtension == "xcactivitylog" }
    return logs.max {
        let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return left < right
    }
}

@_cdecl("cmux_hot_reload_configure")
public func configure() {
    guard engine == nil else { return }
    let sourceRoot = ProcessInfo.processInfo.environment["INJECTION_DIRECTORIES"]?.components(separatedBy: ",").first ?? ""
    if let log = matchingBuildLog(sourceRoot: sourceRoot) {
        UserDefaults.standard.set(log.path, forKey: "HotReloadingBuildLogsDir")
    }
    Recompiler.onCompilationEvent = { _, state, detail in
        var info = ["state": state]
        if let detail { info["error"] = detail }
        NotificationCenter.default.post(name: Notification.Name("CMUX_HOT_RELOAD_COMPILATION"),
                                        object: nil, userInfo: info)
    }
    // Keep recompilation on the engine's background queue. Its sweeper dispatches
    // UI refresh notifications to main after patching.
    engine = InjectionLite()
    // The upstream watcher backdates its first event to recover build history.
    // Prime that bootstrap with a non-source file so the user's first save is live.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        let marker = URL(fileURLWithPath: sourceRoot)
            .appendingPathComponent("Packages/macOS/CmuxHotReloadRuntime/.build/watcher-ready")
        try? String(ProcessInfo.processInfo.processIdentifier).write(to: marker, atomically: true, encoding: .utf8)
    }
}
