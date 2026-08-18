import AppKit
import Foundation

/// Single entry point for "the user activated a web link inside cmux".
///
/// Prefers cmux's own browser so a link stays in the window the user is working
/// in, and falls back to the system browser when the built-in browser is
/// disabled or cannot open a panel. Every surface that activates a link routes
/// through here so the behaviour cannot drift between entrypoints.
@MainActor
enum CmuxLinkOpener {
    /// Where the link ended up. Callers that want to report or log the outcome
    /// can branch on this; most can ignore it.
    enum Destination {
        case cmuxBrowser
        case systemBrowser
    }

    @discardableResult
    static func open(_ url: URL) -> Destination {
        if AppDelegate.shared?.openBrowserAndFocusAddressBar(url: url) != nil {
            return .cmuxBrowser
        }
        NSWorkspace.shared.open(url)
        return .systemBrowser
    }

    /// Force the system browser, for the escape hatch where the user
    /// explicitly wants Chrome (extensions, an existing signed-in session, a
    /// site WebKit renders badly).
    static func openExternally(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
