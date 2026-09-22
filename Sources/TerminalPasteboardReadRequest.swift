import AppKit

/// Identifies a pasteboard generation and preserves short plain-text-only pastes across clipboard restoration.
struct TerminalPasteboardReadRequest: Codable, Sendable {
    let pasteboardName: String
    let changeCount: Int
    let plainTextSnapshot: String?

    init(
        pasteboardName: String,
        changeCount: Int,
        plainTextSnapshot: String? = nil
    ) {
        self.pasteboardName = pasteboardName
        self.changeCount = changeCount
        self.plainTextSnapshot = plainTextSnapshot
    }

    @MainActor
    init(pasteboard: NSPasteboard) {
        let generation = pasteboard.changeCount
        // Dictation tools restore the clipboard shortly after invoking Paste.
        // Capture a plain-text-only payload before worker startup or FIFO delay.
        // Rich content, files, and promised media still use the isolated worker.
        let plainTypes: Set<NSPasteboard.PasteboardType> = [
            .string, NSPasteboard.PasteboardType("NSStringPboardType"),
        ]
        let types = Set(pasteboard.types ?? [])
        var text: String?
        if types.contains(.string), types.isSubset(of: plainTypes),
           let value = pasteboard.string(forType: .string),
           value.utf8.count <= 1024 * 1024,
           pasteboard.changeCount == generation {
            text = value
        }
        self.init(
            pasteboardName: pasteboard.name.rawValue,
            changeCount: generation,
            plainTextSnapshot: text
        )
    }
}
