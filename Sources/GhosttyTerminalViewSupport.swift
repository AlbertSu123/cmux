import AppKit
import CmuxTerminal
import GhosttyKit

final class GhosttyPassthroughVisualEffectView: NSVisualEffectView {
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class TerminalLinkHoverIndicatorView: NSView {
    private let backdrop = GhosttyPassthroughVisualEffectView(frame: .zero)
    private let label = NSTextField(labelWithString: "")
    private var url: String?
    private var linkActive = false

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 6
        backdrop.layer?.masksToBounds = true
        backdrop.layer?.borderWidth = 1
        backdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        backdrop.alphaValue = 0.96

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(backdrop)
        backdrop.addSubview(label)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            backdrop.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setURL(_ url: String?) {
        self.url = url?.isEmpty == false ? url : nil
        refreshLabel()
    }

    func setLinkActive(_ active: Bool) {
        linkActive = active
        if !active { url = nil }
        refreshLabel()
    }

    private func refreshLabel() {
        let target = url.flatMap { resolveTerminalOpenURLTarget($0) }
        let applicationName = target.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0.url) }
            .map { applicationURL in
                let application = Bundle(url: applicationURL)
                return application?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? application?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? applicationURL.deletingPathExtension().lastPathComponent
            }
        let hint: String
        if case .external(let destination) = target {
            if destination.isFileURL {
                // Local files may use cmux or the preferred editor, so do not
                // promise the system's file handler here.
                hint = String(localized: "terminal.linkHover.fileHint", defaultValue: "⌘ Click: open file")
            } else if let applicationName {
                hint = String(format: String(localized: "terminal.linkHover.applicationHint",
                                             defaultValue: "⌘ Click: %@"), applicationName)
            } else {
                hint = String(localized: "terminal.linkHover.openHint", defaultValue: "⌘ Click: open link")
            }
        } else if let applicationName {
            hint = String(format: String(localized: "terminal.linkHover.namedBrowserHint",
                                         defaultValue: "⌘ Click: cmux browser · ⌥ Click: %@"), applicationName)
        } else {
            hint = String(localized: "terminal.linkHover.browserHint",
                          defaultValue: "⌘ Click: cmux browser · ⌥ Click: default browser")
        }
        let text = url.map { "\($0)  ·  \(hint)" } ?? hint
        label.stringValue = text
        label.setAccessibilityLabel(text)
        isHidden = !linkActive && url == nil
    }

}

extension GhosttySurfaceScrollView {
    nonisolated static func linkHoverURL(from link: ghostty_action_mouse_over_link_s) -> String? {
        guard link.len > 0, let bytes = link.url else { return nil }
        return String(data: Data(bytes: bytes, count: Int(link.len)), encoding: .utf8)
    }

    func setLinkHoverURL(_ url: String?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.setLinkHoverURL(url) }
            return
        }
        linkHoverIndicatorView.setURL(url)
    }
}

func shouldAllowEnsureFocusWindowActivation(
    activeTabManager: TabManager?,
    targetTabManager: TabManager,
    keyWindow: NSWindow?,
    mainWindow: NSWindow?,
    targetWindow: NSWindow
) -> Bool {
    guard activeTabManager === targetTabManager || (keyWindow == nil && mainWindow == nil) else {
        return false
    }

    if let keyWindow {
        return keyWindow === targetWindow
    }

    if let mainWindow {
        return mainWindow === targetWindow
    }

    return true
}

extension TerminalSurface {
    func debugInitialCommand() -> String? {
        initialCommand
    }

    func debugTmuxStartCommand() -> String? {
        tmuxStartCommand
    }

    func debugInitialInputMetadata() -> (hasInitialInput: Bool, byteCount: Int) {
        let byteCount = initialInput?.utf8.count ?? 0
        return (byteCount > 0, byteCount)
    }

    func debugInitialInputForTesting() -> String? {
        initialInput
    }
}
