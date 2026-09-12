import Foundation
import Testing
@testable import CmuxUpdater

@Suite struct InstalledBuildMonitorTests {
    private func identity(commit: String?, modified: TimeInterval?) -> InstalledBuildIdentity {
        InstalledBuildIdentity(
            commit: commit,
            executableModifiedAt: modified.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @Test func stampedCommitsDecideWhenBothArePresent() {
        let running = identity(commit: "aaa", modified: 100)
        #expect(InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: "bbb", modified: 50)))
        #expect(!InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: "aaa", modified: 500)))
    }

    @Test func executableDateDecidesWithoutStampedCommits() {
        let running = identity(commit: nil, modified: 100)
        #expect(InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: nil, modified: 101)))
        #expect(!InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: nil, modified: 100)))
        #expect(!InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: nil, modified: 99)))
    }

    @Test func bundleMidReplacementIsNotPending() {
        let running = identity(commit: "aaa", modified: 100)
        #expect(!InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: "bbb", modified: nil)))
        #expect(!InstalledBuildIdentity.relaunchIsPending(running: running, onDisk: identity(commit: nil, modified: nil)))
    }

    @Test func onDiskIdentityReadsInfoPlistAndExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-installed-build-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("cmux.app", isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleExecutable": "cmux", "CMUXInstalledCommit": " abc123 \n"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try Data("bin".utf8).write(to: macOS.appendingPathComponent("cmux"))

        let identity = InstalledBuildIdentity.onDisk(bundleURL: bundle)

        #expect(identity.commit == "abc123")
        #expect(identity.executableModifiedAt != nil)
        #expect(InstalledBuildIdentity.onDisk(bundleURL: root.appendingPathComponent("missing.app")) == InstalledBuildIdentity(commit: nil, executableModifiedAt: nil))
    }
}
