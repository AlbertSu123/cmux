import AppKit
import Foundation
import CmuxTerminal
import Testing
import struct CmuxSettings.AppCatalogSection
import protocol CmuxWorkspaces.FileOpening

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Terminal link open coordinator", .serialized)
struct TerminalLinkOpenCoordinatorTests {
    @Test("Hover hints describe the destination instead of treating every link as a browser link",
          arguments: ["https://example.com", "vnc://example.com", "file:///tmp/cmux-hover-test.txt"])
    @MainActor
    func hoverHintDestination(rawURL: String) throws {
        let indicator = TerminalLinkHoverIndicatorView(frame: .zero)
        indicator.setURL(rawURL)
        let label = try #require(indicator.subviews.flatMap { $0.subviews }
            .compactMap { $0 as? NSTextField }.first)
        #expect(!indicator.isHidden)
        #expect(label.stringValue.contains(rawURL))
        if rawURL.hasPrefix("https:") {
            #expect(label.stringValue.contains("cmux browser"))
            if let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: rawURL)!) {
                let bundle = Bundle(url: handler)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? handler.deletingPathExtension().lastPathComponent
                #expect(label.stringValue.contains(name))
            }
        } else {
            #expect(!label.stringValue.contains("browser"))
            if rawURL.hasPrefix("file:") { #expect(label.stringValue.contains("open file")) }
        }
        indicator.setURL(nil)
        #expect(indicator.isHidden)
    }

    @Test("VNC links remain valid external Screen Sharing targets")
    func vncLinksRouteExternally() throws {
        let defaults = makeDefaults()
        let url = try #require(URL(string: "vnc://100.84.55.24:5900"))
        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, _ in nil },
            externalOpen: { externallyOpened.append($0); return true },
            deferOperation: { operation in operation() }
        )

        #expect(coordinator.open(TerminalLinkOpenRequest(
            browserDestination: .cmux,
            rawValue: url.absoluteString,
            sourceWorkspaceId: nil,
            sourcePanelId: nil,
            workingDirectory: nil
        )))
        #expect(externallyOpened == [url])
        #expect(CmuxLinkOpener.isScreenSharingURL(url))
        #expect(!CmuxLinkOpener.isScreenSharingURL(URL(string: "vnc://")!))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "terminal-link-open-coordinator-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: BrowserAvailabilitySettings.disabledKey)
        defaults.set(true, forKey: BrowserLinkOpenSettings.openTerminalLinksInCmuxBrowserKey)
        defaults.set(
            true,
            forKey: AppCatalogSection().openSupportedFilesInCmux.userDefaultsKey
        )
        return defaults
    }

    @Test("Embedded URL without an owning container falls back externally")
    @MainActor
    func unresolvedSourceFallsBackExternally() throws {
        let defaults = makeDefaults()
        let url = try #require(URL(string: "https://example.com/unresolved"))
        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, _ in nil },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            deferOperation: { operation in operation() }
        )

        let handled = coordinator.open(
            TerminalLinkOpenRequest(
                rawValue: url.absoluteString,
                sourceWorkspaceId: nil,
                sourcePanelId: UUID(),
                workingDirectory: nil
            )
        )

        #expect(handled)
        #expect(externallyOpened == [url])
    }

    @Test("Dock terminal links split once, then reuse the right browser pane")
    @MainActor
    func dockEmbeddedLinksReuseThenSplit() throws {
        let defaults = makeDefaults()
        let store = DockSplitStore(
            workspaceId: UUID(),
            baseDirectoryProvider: { FileManager.default.temporaryDirectory.path },
            browserAvailabilityProvider: { true }
        )
        defer { store.closeAllPanels() }

        let rootPane = try #require(store.bonsplitController.allPaneIds.first)
        let terminalPanelId = try #require(
            store.newSurface(kind: .terminal, inPane: rootPane, focus: true)
        )
        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, panelId in
                panelId == terminalPanelId ? store : nil
            },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            deferOperation: { operation in operation() }
        )
        let firstURL = try #require(URL(string: "https://example.com/first"))
        let secondURL = try #require(URL(string: "https://example.com/second"))

        #expect(coordinator.open(TerminalLinkOpenRequest(
            rawValue: firstURL.absoluteString,
            sourceWorkspaceId: nil,
            sourcePanelId: terminalPanelId,
            workingDirectory: nil
        )))
        #expect(store.bonsplitController.allPaneIds.count == 2)

        #expect(coordinator.open(TerminalLinkOpenRequest(
            rawValue: secondURL.absoluteString,
            sourceWorkspaceId: nil,
            sourcePanelId: terminalPanelId,
            workingDirectory: nil
        )))
        #expect(store.bonsplitController.allPaneIds.count == 2)

        let browserPanels = store.bonsplitController.allTabIds.compactMap {
            store.panel(for: $0) as? BrowserPanel
        }
        #expect(browserPanels.count == 2)
        #expect(Set(browserPanels.compactMap { $0.preferredURLStringForOmnibar() }) == [
            firstURL.absoluteString,
            secondURL.absoluteString,
        ])
        #expect(externallyOpened.isEmpty)
    }

    @Test(
        "Visible HTML paths open in Browser instead of File Preview",
        arguments: ["html", "htm"]
    )
    @MainActor
    func visibleHTMLPathOpensInBrowser(pathExtension: String) throws {
        _ = NSApplication.shared
        let defaults = makeDefaults()
        let htmlURL = try makeHTMLFixture(pathExtension: pathExtension)
        defer { try? FileManager.default.removeItem(at: htmlURL.deletingLastPathComponent()) }

        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let sourcePanelId = try #require(workspace.focusedPanelId)

        #expect(CommandClickFileOpenRouter.openInCmux(
            workspace: workspace,
            sourcePanelId: sourcePanelId,
            filePath: htmlURL.path,
            defaults: defaults
        ))

        let browser = try #require(
            workspace.panels.values.compactMap { $0 as? BrowserPanel }.first
        )
        #expect(browser.currentURL?.standardizedFileURL == htmlURL.standardizedFileURL)
        #expect(!workspace.panels.values.contains { $0 is FilePreviewPanel })
    }

    @Test("Dock HTML paths open in Browser instead of externally")
    @MainActor
    func dockHTMLPathOpensInBrowser() throws {
        let defaults = makeDefaults()
        let htmlURL = try makeHTMLFixture(pathExtension: "html")
        defer { try? FileManager.default.removeItem(at: htmlURL.deletingLastPathComponent()) }

        let store = DockSplitStore(
            workspaceId: UUID(),
            baseDirectoryProvider: { FileManager.default.temporaryDirectory.path },
            browserAvailabilityProvider: { true }
        )
        defer { store.closeAllPanels() }

        let rootPane = try #require(store.bonsplitController.allPaneIds.first)
        let terminalPanelId = try #require(
            store.newSurface(kind: .terminal, inPane: rootPane, focus: true)
        )
        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, panelId in
                panelId == terminalPanelId ? store : nil
            },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            deferOperation: { operation in operation() }
        )

        #expect(coordinator.open(TerminalLinkOpenRequest(
            rawValue: htmlURL.path,
            sourceWorkspaceId: nil,
            sourcePanelId: terminalPanelId,
            workingDirectory: nil
        )))

        let browserPanels = store.bonsplitController.allTabIds.compactMap {
            store.panel(for: $0) as? BrowserPanel
        }
        #expect(browserPanels.count == 1)
        #expect(browserPanels.first?.currentURL?.standardizedFileURL == htmlURL.standardizedFileURL)
        #expect(externallyOpened.isEmpty)
    }

    @Test("Local file external opens honor the preferred editor, not the raw system opener")
    @MainActor
    func localFileExternalOpenHonorsPreferredEditor() throws {
        let defaults = makeDefaults()
        // The reporter's configuration from issue #10222: a preferred editor is
        // set, terminal links in the cmux browser are off, and supported-file
        // routing is off, so the file must go to exactly one external handler —
        // the preferred editor.
        defaults.set(
            "/usr/bin/true",
            forKey: AppCatalogSection().preferredEditor.userDefaultsKey
        )
        defaults.set(false, forKey: BrowserLinkOpenSettings.openTerminalLinksInCmuxBrowserKey)
        defaults.set(
            false,
            forKey: AppCatalogSection().openSupportedFilesInCmux.userDefaultsKey
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-preferred-editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, _ in nil },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            deferOperation: { operation in operation() }
        )

        let handled = coordinator.open(
            TerminalLinkOpenRequest(
                rawValue: fileURL.path,
                sourceWorkspaceId: nil,
                sourcePanelId: UUID(),
                workingDirectory: nil
            )
        )

        #expect(handled)
        #expect(
            externallyOpened.isEmpty,
            "A local file open must be routed through the preferred-editor seam when app.preferredEditor is configured, never handed to the raw system opener (issue #10222)."
        )
    }

    @Test("Local file external opens are handed to the injected file-opening seam")
    @MainActor
    func localFileExternalOpenRoutesThroughFileOpeningSeam() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: BrowserLinkOpenSettings.openTerminalLinksInCmuxBrowserKey)
        defaults.set(
            false,
            forKey: AppCatalogSection().openSupportedFilesInCmux.userDefaultsKey
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-open-seam-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

        var externallyOpened: [URL] = []
        let fileOpener = RecordingFileOpener()
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, _ in nil },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            fileOpen: fileOpener,
            deferOperation: { operation in operation() }
        )

        let handled = coordinator.open(
            TerminalLinkOpenRequest(
                rawValue: fileURL.path,
                sourceWorkspaceId: nil,
                sourcePanelId: UUID(),
                workingDirectory: nil
            )
        )

        #expect(handled)
        #expect(fileOpener.opened == [URL(fileURLWithPath: fileURL.path)])
        #expect(externallyOpened.isEmpty)
    }

    @Test("Web URLs still open through the raw system opener with a preferred editor configured")
    @MainActor
    func webURLExternalOpenIgnoresPreferredEditor() throws {
        let defaults = makeDefaults()
        defaults.set(
            "/usr/bin/true",
            forKey: AppCatalogSection().preferredEditor.userDefaultsKey
        )
        defaults.set(false, forKey: BrowserLinkOpenSettings.openTerminalLinksInCmuxBrowserKey)

        let url = try #require(URL(string: "https://example.com/reference"))
        var externallyOpened: [URL] = []
        let fileOpener = RecordingFileOpener()
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, _ in nil },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            fileOpen: fileOpener,
            deferOperation: { operation in operation() }
        )

        let handled = coordinator.open(
            TerminalLinkOpenRequest(
                rawValue: url.absoluteString,
                sourceWorkspaceId: nil,
                sourcePanelId: UUID(),
                workingDirectory: nil
            )
        )

        #expect(handled)
        #expect(externallyOpened == [url])
        #expect(fileOpener.opened.isEmpty)
    }

    @Test("Configured external URL rules bypass the embedded terminal browser")
    @MainActor
    func configuredExternalURLRuleUsesSystemBrowser() throws {
        let defaults = makeDefaults()
        defaults.set(
            [".*example\\.com.*"],
            forKey: BrowserLinkOpenSettings.browserExternalOpenPatternsKey
        )

        let store = DockSplitStore(
            workspaceId: UUID(),
            baseDirectoryProvider: { FileManager.default.temporaryDirectory.path },
            browserAvailabilityProvider: { true }
        )
        defer { store.closeAllPanels() }
        let rootPane = try #require(store.bonsplitController.allPaneIds.first)
        let terminalPanelId = try #require(
            store.newSurface(kind: .terminal, inPane: rootPane, focus: true)
        )
        let url = try #require(URL(string: "https://example.com/"))
        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, panelId in
                panelId == terminalPanelId ? store : nil
            },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return true
            },
            deferOperation: { operation in operation() }
        )

        #expect(coordinator.open(TerminalLinkOpenRequest(
            rawValue: url.absoluteString,
            sourceWorkspaceId: nil,
            sourcePanelId: terminalPanelId,
            workingDirectory: nil
        )))
        #expect(externallyOpened == [url])
        #expect(
            store.bonsplitController.allTabIds.compactMap { store.panel(for: $0) as? BrowserPanel }.isEmpty
        )
    }

    @Test("Configured external URL opener failure does not fall back to embedded browser")
    @MainActor
    func configuredExternalURLRulePropagatesOpenerFailure() throws {
        let defaults = makeDefaults()
        defaults.set(
            ["example.com"],
            forKey: BrowserLinkOpenSettings.browserExternalOpenPatternsKey
        )

        let store = DockSplitStore(
            workspaceId: UUID(),
            baseDirectoryProvider: { FileManager.default.temporaryDirectory.path },
            browserAvailabilityProvider: { true }
        )
        defer { store.closeAllPanels() }
        let rootPane = try #require(store.bonsplitController.allPaneIds.first)
        let terminalPanelId = try #require(
            store.newSurface(kind: .terminal, inPane: rootPane, focus: true)
        )
        let url = try #require(URL(string: "https://example.com/"))
        var externallyOpened: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, panelId in
                panelId == terminalPanelId ? store : nil
            },
            externalOpen: { openedURL in
                externallyOpened.append(openedURL)
                return false
            },
            deferOperation: { operation in operation() }
        )

        #expect(!coordinator.open(TerminalLinkOpenRequest(
            rawValue: url.absoluteString,
            sourceWorkspaceId: nil,
            sourcePanelId: terminalPanelId,
            workingDirectory: nil
        )))
        #expect(externallyOpened == [url])
        #expect(
            store.bonsplitController.allTabIds.compactMap { store.panel(for: $0) as? BrowserPanel }.isEmpty
        )
    }

    @Test("Explicit click destination overrides the configured browser", arguments: [true, false])
    @MainActor
    func explicitClickDestination(useSystemBrowser: Bool) throws {
        let defaults = makeDefaults()
        // Set the opposite preference so this exercises the explicit override.
        defaults.set(useSystemBrowser, forKey: BrowserLinkOpenSettings.openTerminalLinksInCmuxBrowserKey)
        defaults.set([".*example.*"], forKey: BrowserLinkOpenSettings.browserExternalOpenPatternsKey)
        let store = DockSplitStore(
            workspaceId: UUID(),
            baseDirectoryProvider: { FileManager.default.temporaryDirectory.path },
            browserAvailabilityProvider: { true }
        )
        defer { store.closeAllPanels() }
        let pane = try #require(store.bonsplitController.allPaneIds.first)
        let panel = try #require(store.newSurface(kind: .terminal, inPane: pane, focus: true))
        let url = try #require(URL(string: "https://example.com/click-destination"))
        var externalURLs: [URL] = []
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: defaults,
            containerResolver: { _, _ in store },
            externalOpen: { externalURLs.append($0); return true },
            deferOperation: { $0() }
        )
        #expect(coordinator.open(TerminalLinkOpenRequest(
            browserDestination: useSystemBrowser ? .system : .cmux,
            rawValue: url.absoluteString,
            sourceWorkspaceId: nil,
            sourcePanelId: panel,
            workingDirectory: nil
        )))
        let browsers = store.bonsplitController.allTabIds.compactMap { store.panel(for: $0) as? BrowserPanel }
        #expect(externalURLs == (useSystemBrowser ? [url] : []))
        #expect(browsers.count == (useSystemBrowser ? 0 : 1))
    }

    @Test("Stationary link clicks use the requested browser through native mouse events",
          arguments: ["option", "option-released", "command", "osc8", "text"], [false, true])
    @MainActor
    func stationaryOptionClickOpensWebLink(variant: String, hoverFirst: Bool) async throws {
        let url = "https://example.com/option-test"
        let output = variant == "osc8" ? "\\033]8;;\(url)\\007click me\\033]8;;\\007"
            : variant == "text" ? "ordinary terminal text" : url
        let visibleText = variant == "osc8" ? "click me" : variant == "text" ? output : url
        let flags: NSEvent.ModifierFlags = variant == "command" ? .command : .option
        let store = DockSplitStore(workspaceId: UUID(), baseDirectoryProvider: { "/tmp" })
        defer { store.closeAllPanels() }
        let pane = try #require(store.bonsplitController.allPaneIds.first)
        let panelID = try #require(store.newSurface(
            kind: .terminal, inPane: pane,
            command: "/bin/sh -c 'printf \"\\033[2J\\033[H\(output)\"; sleep 30'",
            focus: true
        ))
        let panel = try #require(store.panels[panelID] as? TerminalPanel)
        let surface = panel.surface
        let host = surface.hostedView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 320)
        window.makeKeyAndOrderFront(nil)
        host.attachSurface(surface)
        host.setVisibleInUI(true)
        host.setActive(true)
        let deadline = Date().addingTimeInterval(5)
        while surface.readText(region: .screen)?.contains(visibleText) != true, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(surface.readText(region: .screen)?.contains(visibleText) == true)
        let view = try #require(host.subviews.compactMap { $0 as? NSScrollView }.first?
            .documentView?.subviews.first as? GhosttyNSView)
        let runtime = try #require(surface.surface)
        window.makeFirstResponder(view)
        view.desiredFocus = true
        try #require(view.terminalPointerShouldForwardActivation())
        let point = NSPoint(x: 30, y: view.bounds.height - 10)
        let location = view.convert(point, to: nil)
        var opened: [TerminalLinkOpenRequest] = []
        GhosttyNSView.debugTerminalLinkOpenHandler = { source, request in
            if source === view { opened.append(request) }
            // Opt-in local smoke check uses the real LaunchServices browser opener.
            // Normal regression runs remain free of external app/network effects.
            if variant == "option", UserDefaults.standard.bool(forKey: "debugOptionClickLiveBrowserSmoke") {
                let handled = TerminalLinkOpenCoordinator().open(request)
                print("Option-click live browser smoke: \(handled)")
                return handled
            }
            return true
        }
        defer { GhosttyNSView.debugTerminalLinkOpenHandler = nil }
        // Cache a no-link hover with Option already down, then click the SAME cell.
        ghostty_surface_mouse_pos(runtime, point.x, 10,
                                  variant == "command" ? GHOSTTY_MODS_SUPER : GHOSTTY_MODS_ALT)
        if hoverFirst {
            let hover = try #require(NSEvent.mouseEvent(
                with: .mouseMoved, location: location, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
            // Exercise both moving over a link and changing modifiers without moving.
            view.mouseMoved(with: hover)
            let changed = try #require(NSEvent.keyEvent(
                with: .flagsChanged, location: location, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: variant == "command" ? 55 : 58
            ))
            view.flagsChanged(with: changed)
            try await Task.sleep(for: .milliseconds(50))
            #expect(host.linkHoverIndicatorView.isHidden == (variant == "text"))
        }
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: location, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: location,
            modifierFlags: variant == "option-released" ? [] : flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 0
        ))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        if variant == "text" {
            #expect(opened.isEmpty)
        } else {
            #expect(opened.count == 1)
            #expect(opened.first?.rawValue == url)
            #expect(opened.first?.browserDestination == (variant == "command" ? .cmux : .system))
        }
    }

    private func makeHTMLFixture(pathExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-html-click-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("index.\(pathExtension)")
        try "<h1>hello</h1><p style=\"color:green\">rendered</p>".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        return fileURL
    }
}

/// Records URLs handed to the coordinator's file-opening seam.
@MainActor
private final class RecordingFileOpener: FileOpening {
    private(set) var opened: [URL] = []

    func open(_ url: URL) {
        opened.append(url)
    }
}
