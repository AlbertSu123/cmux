import AppKit
import Testing
import CmuxTerminal

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Terminal search overlay mouse release", .serialized)
struct TerminalSearchOverlayMouseReleaseTests {
    @Test("Search overlay forwards terminal mouse release during selection drag")
    func searchOverlayForwardsTerminalMouseReleaseDuringSelectionDrag() throws {
        let surface = makeTerminalSurface()
        defer { surface.releaseSurfaceForTesting() }

        let (hostedView, window) = try attachToWindow(surface: surface)
        defer { window.orderOut(nil) }

        hostedView.setSearchOverlay(searchState: TerminalSurface.SearchState(needle: "needle"))
        #expect(waitUntil(description: "search overlay to mount") {
            hostedView.debugHasSearchOverlay()
        })

        let terminalView = try #require(surfaceView(in: hostedView) as? GhosttyNSView)
        let overlay = try #require(hostedView.debugSearchOverlayHostingViewForTesting())

        let downLocation = terminalView.convert(NSPoint(x: 24, y: 24), to: nil)
        terminalView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: downLocation, window: window))
        #expect(
            hostedView.debugSurfaceHasPendingLeftMouseReleaseForTesting(),
            "Terminal selection should own the left-button release after mouseDown"
        )

        let overlayLocation = overlay.convert(NSPoint(x: overlay.bounds.midX, y: overlay.bounds.midY), to: nil)
        overlay.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: overlayLocation, window: window))
        #expect(
            hostedView.debugSurfaceHasPendingLeftMouseReleaseForTesting(),
            "Dragging across the find overlay must keep terminal selection ownership until mouseUp"
        )

        overlay.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: overlayLocation, window: window))
        #expect(
            !hostedView.debugSurfaceHasPendingLeftMouseReleaseForTesting(),
            "An overlay-captured mouseUp must release the terminal selection"
        )
    }

    @Test("Search overlay release clears pending selection after surface release")
    func searchOverlayMouseReleaseClearsSelectionDragAfterSurfaceRelease() throws {
        let surface = makeTerminalSurface()
        defer { surface.releaseSurfaceForTesting() }

        let (hostedView, window) = try attachToWindow(surface: surface)
        defer { window.orderOut(nil) }

        hostedView.setSearchOverlay(searchState: TerminalSurface.SearchState(needle: "needle"))
        #expect(waitUntil(description: "search overlay to mount") {
            hostedView.debugHasSearchOverlay()
        })

        let terminalView = try #require(surfaceView(in: hostedView) as? GhosttyNSView)
        let overlay = try #require(hostedView.debugSearchOverlayHostingViewForTesting())

        let downLocation = terminalView.convert(NSPoint(x: 24, y: 24), to: nil)
        terminalView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: downLocation, window: window))
        #expect(hostedView.debugSurfaceHasPendingLeftMouseReleaseForTesting())

        surface.releaseSurfaceForTesting()
        #expect(surface.surface == nil)

        let overlayLocation = overlay.convert(NSPoint(x: overlay.bounds.midX, y: overlay.bounds.midY), to: nil)
        overlay.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: overlayLocation, window: window))
        #expect(
            !hostedView.debugSurfaceHasPendingLeftMouseReleaseForTesting(),
            "The pending terminal release state must clear even if the Ghostty surface is gone"
        )
    }

    @Test("Stationary Option-click reaches the system browser through native mouse events")
    func stationaryOptionClickOpensWebLink() throws {
        let url = "https://example.com/option-test"
        let surface = TerminalSurface(
            tabId: UUID(), context: GHOSTTY_SURFACE_CONTEXT_SPLIT,
            configTemplate: nil, workingDirectory: nil,
            initialCommand: "/bin/sh -c 'printf \"\\033[2J\\033[Hhttps://example.com/option-test\"; sleep 30'"
        )
        defer { surface.releaseSurfaceForTesting() }
        let (host, window) = try attachToWindow(surface: surface)
        defer { window.orderOut(nil) }
        #expect(waitUntil(timeout: 5, description: "fixture output") {
            surface.readText(region: .screen)?.contains(url) == true
        })
        let view = try #require(surfaceView(in: host) as? GhosttyNSView)
        let runtime = try #require(surface.surface)
        let point = NSPoint(x: 30, y: view.bounds.height - 10)
        let location = view.convert(point, to: nil)
        var opened: [TerminalLinkOpenRequest] = []
        GhosttyNSView.debugTerminalLinkOpenHandler = { source, request in
            if source === view { opened.append(request) }
            return true
        }
        defer { GhosttyNSView.debugTerminalLinkOpenHandler = nil }
        // Cache a no-link hover with Option already down, then click the SAME cell.
        ghostty_surface_mouse_pos(runtime, point.x, 10, GHOSTTY_MODS_ALT)
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: location, modifierFlags: .option,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: location, modifierFlags: .option,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 0
        ))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        #expect(opened.count == 1)
        #expect(opened.first?.rawValue == url)
        #expect(opened.first?.browserDestination == .system)
    }

    private func makeTerminalSurface() -> TerminalSurface {
        TerminalSurface(
            tabId: UUID(),
            context: GHOSTTY_SURFACE_CONTEXT_SPLIT,
            configTemplate: nil,
            workingDirectory: nil
        )
    }

    private func attachToWindow(surface: TerminalSurface) throws -> (GhosttySurfaceScrollView, NSWindow) {
        let hostedView = surface.hostedView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        hostedView.frame = contentView.bounds
        hostedView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostedView)

        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        hostedView.layoutSubtreeIfNeeded()

        return (hostedView, window)
    }

    private func makeMouseEvent(type: NSEvent.EventType, location: NSPoint, window: NSWindow) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        ) else {
            preconditionFailure("Failed to create \(type) mouse event")
        }
        return event
    }

    private func surfaceView(in hostedView: GhosttySurfaceScrollView) -> NSView? {
        hostedView.subviews
            .compactMap { $0 as? NSScrollView }
            .first?
            .documentView?
            .subviews
            .first
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        description: String,
        _ condition: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}
