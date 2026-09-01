import Foundation

/// Writes a parsed CSV/TSV table back out as text.
///
/// Round-tripping is lossy by nature — the parser discards the original
/// quoting style and line endings — so this normalises: RFC 4180 quoting,
/// only where a field needs it, and `\n` terminators.
enum FilePreviewCSVSerializer {
    /// Quote a single field, doubling any embedded quotes.
    ///
    /// A field needs quoting when it contains the delimiter, a quote, a
    /// newline, or leading/trailing whitespace that would otherwise be lost.
    static func field(_ value: String, delimiter: Character) -> String {
        let needsQuoting =
            value.contains(delimiter)
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
            || value.first?.isWhitespace == true
            || value.last?.isWhitespace == true
        guard needsQuoting else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func line(_ cells: [String], delimiter: Character) -> String {
        cells.map { field($0, delimiter: delimiter) }.joined(separator: String(delimiter))
    }

    static func serialize(
        header: [String],
        rows: [[String]],
        delimiter: Character
    ) -> String {
        var out = line(header, delimiter: delimiter)
        out.append("\n")
        for row in rows {
            out.append(line(row, delimiter: delimiter))
            out.append("\n")
        }
        return out
    }

    /// Write the table to `url`, replacing the file atomically so a crash
    /// mid-write cannot leave a half-truncated CSV behind.
    static func write(
        header: [String],
        rows: [[String]],
        delimiter: Character,
        to url: URL
    ) throws {
        let text = serialize(header: header, rows: rows, delimiter: delimiter)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
