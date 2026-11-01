/// The lexical search of ADR-0141 until roadmap 0181's index: every word must appear, case-insensitively, in one of an entry's fields;
/// matches whose words sit in earlier fields come first, then in list order.
public enum ListSearch {
    public static func rank<Entry>(_ entries: [Entry], words text: String, fields: (Entry) -> [String]) -> [Entry] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        var scored: [(score: Int, index: Int, entry: Entry)] = []
        for (index, entry) in entries.enumerated() {
            let haystacks = fields(entry).map { $0.lowercased() }
            var score = 0
            var all = true
            for word in words {
                guard let field = haystacks.firstIndex(where: { $0.contains(word) }) else {
                    all = false
                    break
                }
                score += field
            }
            if all { scored.append((score, index, entry)) }
        }
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.entry)
    }
}
