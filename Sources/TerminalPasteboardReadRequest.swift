import AppKit
import ApplicationServices

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
           Self.hasMaterializedText(in: pasteboard),
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

    // A promised string can invoke a blocked provider. Only capture text that
    // the pasteboard server already holds; leave lazy providers in the worker.
    @MainActor
    private static func hasMaterializedText(in pasteboard: NSPasteboard) -> Bool {
        var reference: Pasteboard?
        guard PasteboardCreate(pasteboard.name.rawValue as CFString, &reference) == noErr,
              let reference else { return false }
        _ = PasteboardSynchronize(reference)
        var count = 0
        var item: PasteboardItemID?
        guard PasteboardGetItemCount(reference, &count) == noErr, count == 1,
              PasteboardGetItemIdentifier(reference, 1, &item) == noErr,
              let item else { return false }
        var flags: PasteboardFlavorFlags = []
        return PasteboardGetItemFlavorFlags(
            reference, item, NSPasteboard.PasteboardType.string.rawValue as CFString, &flags
        ) == noErr && !flags.contains(.promised)
    }

}
