internal import TerminalKitText

/// What a selection reads from the conversation: each transcript item is a block, and its text as the screen wraps it is the block's
/// lines (TerminalKit roadmap 0017).
///
/// It is the item's own text, not what is drawn: no `›` before a prompt, no padding, no status. A tab is four spaces, because that
/// is what the wrapping measured and what the highlight's columns count.
struct TranscriptContent: SelectableContent {
    typealias BlockID = Int

    /// The hard lines of each item, in order.
    var blocks: [[String]]

    init(blocks: [[String]] = []) { self.blocks = blocks }

    init(_ transcript: Transcript) {
        blocks = transcript.items.indices.map { Self.hardLines(of: transcript.contentText(at: $0)) }
    }

    /// The lines of `text` as `TextWrap` sees them: tabs expanded, split at line feeds.
    static func hardLines(of text: String) -> [String] {
        // Most text has no tab, and the replacement is a search through all of it.
        let expanded = text.utf8.contains(0x09) ? text.replacing("\t", with: "    ") : text
        return expanded.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// How many lines ``hardLines(of:)`` finds in `text`, without building them: a folded block's header counts its output's lines.
    static func hardLineCount(of text: String) -> Int {
        text.utf8.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    var blockCount: Int { blocks.count }
    func ordinal(of block: Int) -> Int? { blocks.indices.contains(block) ? block : nil }
    func blockID(at ordinal: Int) -> Int { ordinal }
    func lineCount(ofBlockAt ordinal: Int) -> Int { blocks[ordinal].count }
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String { blocks[ordinal][line] }
}
