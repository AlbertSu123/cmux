import Foundation

extension AgentLaunchSanitizer {
    /// Keeps only the last occurrence of every option in `policy.lastOccurrenceWinsOptions`.
    ///
    /// Later occurrences win because that is what the agent applied when the
    /// argv was accepted at launch: a wrapper's default precedes the user's
    /// explicit value, and a subcommand's flag follows the top-level one.
    static func collapsingRepeatedOptions(_ tokens: [String], policy: Policy) -> [String] {
        guard !policy.lastOccurrenceWinsOptions.isEmpty else { return tokens }
        var spans: [(group: Int?, range: Range<Int>)] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard isOptionToken(token), token != "-" else {
                spans.append((nil, index..<(index + 1)))
                index += 1
                continue
            }
            let width = max(1, optionWidth(tokens, index: index, policy: policy))
            let end = min(tokens.count, index + width)
            spans.append((repeatedOptionGroup(of: token, policy: policy), index..<end))
            index = end
        }
        var lastSpanByGroup: [Int: Int] = [:]
        for (spanIndex, span) in spans.enumerated() {
            if let group = span.group { lastSpanByGroup[group] = spanIndex }
        }
        var result: [String] = []
        for (spanIndex, span) in spans.enumerated() {
            if let group = span.group, lastSpanByGroup[group] != spanIndex { continue }
            result.append(contentsOf: tokens[span.range])
        }
        return result
    }

    private static func repeatedOptionGroup(of token: String, policy: Policy) -> Int? {
        let name = token.firstIndex(of: "=").map { String(token[..<$0]) } ?? token
        return policy.lastOccurrenceWinsOptions.firstIndex { $0.contains(name) }
    }
}
