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
        text.replacing("\t", with: "    ").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var blockCount: Int { blocks.count }
    func ordinal(of block: Int) -> Int? { blocks.indices.contains(block) ? block : nil }
    func blockID(at ordinal: Int) -> Int { ordinal }
    func lineCount(ofBlockAt ordinal: Int) -> Int { blocks[ordinal].count }
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String { blocks[ordinal][line] }
}
