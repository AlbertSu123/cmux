import Foundation

/// Immutable context captured when Ghostty asks cmux to open a terminal link.
struct TerminalLinkOpenRequest: Sendable {
    enum BrowserDestination: Sendable {
        case configured
        case cmux
        case system
    }

    var browserDestination: BrowserDestination = .configured
    let rawValue: String
    let sourceWorkspaceId: UUID?
    let sourcePanelId: UUID?
    let workingDirectory: String?
}
