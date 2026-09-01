import Foundation

/// Recognises the cell values in a CSV that are worth opening: web URLs and
/// email addresses.
///
/// Deliberately conservative — a cell only resolves to a link when the whole
/// value, or its first separated token, is unambiguously one. Anything with
/// interior spaces, or an address-like fragment buried in prose, is left as
/// plain text so a stray `@` in a sentence never renders as a mailto.
enum FilePreviewCSVCellLink {
    /// Separators used by columns that pack several links into one cell
    /// (for example `"https://a.example ; https://b.example"`).
    private static let separators = CharacterSet(charactersIn: ";,|").union(.whitespacesAndNewlines)

    static func url(for cell: String) -> URL? {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return nil }
        if let url = urlForSingleToken(trimmed) { return url }
        // Fall back to the first token so multi-link cells stay actionable.
        guard let first = trimmed
            .components(separatedBy: separators)
            .first(where: { !$0.isEmpty })
        else { return nil }
        return first == trimmed ? nil : urlForSingleToken(first)
    }

    private static func urlForSingleToken(_ token: String) -> URL? {
        guard !token.isEmpty, token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        let lowercased = token.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return URL(string: token)
        }
        if lowercased.hasPrefix("mailto:") {
            return URL(string: token)
        }
        if lowercased.hasPrefix("www."), token.contains(".") {
            return URL(string: "https://\(token)")
        }
        if isEmailAddress(token) {
            return URL(string: "mailto:\(token)")
        }
        return nil
    }

    private static func isEmailAddress(_ token: String) -> Bool {
        let parts = token.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, domain.contains(".") else { return false }
        guard let lastLabel = domain.split(separator: ".").last, lastLabel.count >= 2 else {
            return false
        }
        guard !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return lastLabel.allSatisfy { $0.isLetter }
    }
}
