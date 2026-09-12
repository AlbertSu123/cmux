public import Foundation
import AppKit
import Observation

/// Identifies one build of the app bundle on disk.
///
/// The fork's install script stamps `CMUXInstalledCommit` into the bundle's
/// Info.plist, so two installs of the same version string still compare
/// distinct. The executable's modification date covers bundles without the
/// stamp, such as plain Xcode builds.
public struct InstalledBuildIdentity: Equatable, Sendable {
    public let commit: String?
    public let executableModifiedAt: Date?

    public init(commit: String?, executableModifiedAt: Date?) {
        self.commit = commit
        self.executableModifiedAt = executableModifiedAt
    }

    /// Reads the identity of the bundle at `bundleURL` from disk, bypassing
    /// the caches that `Bundle` keeps for the running process.
    public static func onDisk(
        bundleURL: URL,
        fileManager: FileManager = .default
    ) -> InstalledBuildIdentity {
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist"))
        let commit = (info?["CMUXInstalledCommit"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let executableName = info?["CFBundleExecutable"] as? String
        let executableModifiedAt = executableName.flatMap { name -> Date? in
            let executable = contents
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(name)
            let attributes = try? fileManager.attributesOfItem(atPath: executable.path)
            return attributes?[.modificationDate] as? Date
        }
        return InstalledBuildIdentity(
            commit: commit.flatMap { $0.isEmpty ? nil : $0 },
            executableModifiedAt: executableModifiedAt
        )
    }

    /// Whether `onDisk` is a different build than `running`.
    ///
    /// A missing on-disk executable means the bundle is mid-replacement, which
    /// is not yet a new build to relaunch into.
    public static func relaunchIsPending(
        running: InstalledBuildIdentity,
        onDisk: InstalledBuildIdentity
    ) -> Bool {
        guard onDisk.executableModifiedAt != nil else { return false }
        if let runningCommit = running.commit, let onDiskCommit = onDisk.commit {
            return runningCommit != onDiskCommit
        }
        guard let runningDate = running.executableModifiedAt,
              let onDiskDate = onDisk.executableModifiedAt else {
            return false
        }
        return onDiskDate > runningDate
    }
}

/// Watches the running app's bundle for an install that landed after launch.
///
/// The fork's install pipeline replaces the bundle under the running process;
/// nothing tells the app, so the sidebar's restart control had no way to show
/// that a relaunch would change anything. The monitor re-reads the bundle's
/// identity when its parent directory changes and when the app activates.
@MainActor
@Observable
public final class InstalledBuildMonitor {
    /// The build on disk when it differs from the running one, else `nil`.
    public private(set) var pendingBuild: InstalledBuildIdentity?
    public let runningBuild: InstalledBuildIdentity

    @ObservationIgnored private let bundleURL: URL
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var directorySource: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var scheduledRefresh: DispatchWorkItem?

    /// Bundle replacement is a move followed by a copy; wait for the copy to
    /// settle before reading the new Info.plist.
    private static let settleDelay: DispatchTimeInterval = .seconds(2)

    public init(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) {
        self.bundleURL = bundleURL
        self.fileManager = fileManager
        runningBuild = InstalledBuildIdentity.onDisk(bundleURL: bundleURL, fileManager: fileManager)
        watchParentDirectory()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Re-reads the bundle on disk and updates `pendingBuild`.
    public func refresh() {
        let onDisk = InstalledBuildIdentity.onDisk(bundleURL: bundleURL, fileManager: fileManager)
        let pending = InstalledBuildIdentity.relaunchIsPending(running: runningBuild, onDisk: onDisk)
        let next = pending ? onDisk : nil
        if next != pendingBuild {
            pendingBuild = next
        }
    }

    private func watchParentDirectory() {
        let parent = bundleURL.deletingLastPathComponent()
        let descriptor = open(parent.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    private func scheduleRefresh() {
        scheduledRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        scheduledRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }
}
