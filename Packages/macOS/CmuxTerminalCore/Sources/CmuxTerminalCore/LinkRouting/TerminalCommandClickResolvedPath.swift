/// Represents an existing local path resolved under the pointer.
public struct TerminalCommandClickResolvedPath: Equatable, Sendable {
    /// The absolute path to open.
    public let path: String
    /// The terminal-text source that produced the path.
    public let source: TerminalCommandClickPathResolutionSource
    /// Whether cmux would open this path itself rather than hand it to the
    /// system. Supplied by the caller because the decision belongs to the app
    /// layer's file-route settings, which this package cannot see.
    public let opensInCmux: Bool

    /// Creates a resolved local-path candidate.
    ///
    /// - Parameters:
    ///   - path: The absolute path to open.
    ///   - source: The terminal-text source that produced the path.
    ///   - opensInCmux: Whether cmux itself would open the path.
    public init(
        path: String,
        source: TerminalCommandClickPathResolutionSource,
        opensInCmux: Bool = false
    ) {
        self.path = path
        self.source = source
        self.opensInCmux = opensInCmux
    }
}
