import CmuxTerminal

/// One immutable request submitted to the process-wide paste-preparation lane.
struct TerminalPastePreparationRequest: Codable, Sendable {
    let pasteboard: TerminalPasteboardReadRequest
    let mode: TerminalImageTransferMode?
    let destination: TerminalPastePreparationDestination?
    let snapshotMaximumByteCount: Int?

    /// Already-owned text needs neither pasteboard I/O nor a helper process.
    /// Keeping this inside the preparation lane preserves FIFO and cancellation.
    var capturedPlainTextResult: TerminalPastePreparationResult? {
        guard mode == .paste,
              let text = pasteboard.plainTextSnapshot,
              let destination else { return nil }
        switch destination {
        case .terminal:
            return .terminal(text.isEmpty ? .reject : .insertText(text))
        case .composer:
            return .composer(text.isEmpty ? .reject : .insertText(text))
        }
    }

    init(
        pasteboard: TerminalPasteboardReadRequest,
        mode: TerminalImageTransferMode,
        destination: TerminalPastePreparationDestination
    ) {
        self.pasteboard = pasteboard
        self.mode = mode
        self.destination = destination
        snapshotMaximumByteCount = nil
    }

    init(snapshot request: TerminalPasteboardContentsCaptureRequest) {
        pasteboard = TerminalPasteboardReadRequest(
            pasteboardName: request.pasteboardName,
            changeCount: request.changeCount
        )
        mode = nil
        destination = nil
        snapshotMaximumByteCount = request.maximumByteCount
    }
}
