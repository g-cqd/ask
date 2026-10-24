/// A sigil at the start of the word under the cursor (roadmap 0048): `/` for something to do, `@` for something to point at.
///
/// A trigger fires only at the start of a word. A `/` or `@` inside a word, a path or an address, is text, and nothing outside the
/// sigils asked for is a trigger. The range covers the whole word, so accepting a choice replaces it, while the query stops at the
/// cursor, so filtering follows what was typed. Offsets count characters, as ``PromptEditor/cursor`` does.
struct CompletionTrigger: Sendable, Equatable {
    /// The word, sigil included, as character offsets into the draft.
    let range: Range<Int>
    /// What was typed after the sigil, up to the cursor.
    let query: String

    /// The trigger the cursor is in, or nil.
    /// - Parameters:
    ///   - cursor: how many characters come before the cursor.
    ///   - text: the draft.
    ///   - sigils: the characters that start a trigger here.
    /// - Returns: the trigger, or nil when the cursor is not in a word that starts with one of `sigils`.
    /// - Complexity: O(cursor): the offset is walked once, then the word.
    static func at(cursor: Int, in text: String, sigils: Set<Character>) -> CompletionTrigger? {
        guard cursor >= 0, let end = text.index(text.startIndex, offsetBy: cursor, limitedBy: text.endIndex) else {
            return nil
        }
        var start = end
        var startOffset = cursor
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous].isWhitespace { break }
            start = previous
            startOffset -= 1
        }
        guard start < end, sigils.contains(text[start]) else { return nil }
        var wordEnd = end
        var endOffset = cursor
        while wordEnd < text.endIndex, !text[wordEnd].isWhitespace {
            wordEnd = text.index(after: wordEnd)
            endOffset += 1
        }
        return CompletionTrigger(
            range: startOffset ..< endOffset, query: String(text[text.index(after: start) ..< end]))
    }
}
