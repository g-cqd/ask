/// A `modelScopes` pattern (roadmap 0094): `*` stands for any run of characters, `/` included, `?` for one, and case is ignored.
/// Anything else is itself, so a URL or an address needs no escaping.
struct ScopeGlob: Sendable, Equatable {
    private let pattern: [Character]

    init(_ pattern: String) {
        self.pattern = Array(pattern.lowercased())
    }

    /// Whether the whole of `text` matches.
    func matches(_ text: String) -> Bool {
        let text = Array(text.lowercased())
        var position = 0
        var index = 0
        // The last `*` seen, and where in the text it was last tried up to: on a mismatch it takes one more character.
        var star: Int?
        var resume = 0
        while index < text.count {
            if position < pattern.count, pattern[position] == "*" {
                star = position
                resume = index
                position += 1
            } else if position < pattern.count, pattern[position] == "?" || pattern[position] == text[index] {
                position += 1
                index += 1
            } else if let star {
                position = star + 1
                resume += 1
                index = resume
            } else {
                return false
            }
        }
        while position < pattern.count, pattern[position] == "*" { position += 1 }
        return position == pattern.count
    }
}
