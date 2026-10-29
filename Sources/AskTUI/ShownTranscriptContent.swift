internal import TerminalKitText

/// The transcript as the selection highlight reads it, with folded code as drawn: lines are found when asked for, so nothing is held for
/// the items off screen (roadmap 0088). The highlight only resolves which items a selection names; copying reads ``TranscriptContent``.
struct ShownTranscriptContent: SelectableContent {
    typealias BlockID = Int

    let transcript: Transcript

    var blockCount: Int { transcript.items.count }

    func ordinal(of block: Int) -> Int? { transcript.items.indices.contains(block) ? block : nil }
    func blockID(at ordinal: Int) -> Int { ordinal }
    func lineCount(ofBlockAt ordinal: Int) -> Int { lines(of: ordinal).count }
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String { lines(of: ordinal)[line] }

    private func lines(of ordinal: Int) -> [String] {
        TranscriptContent.hardLines(of: transcript.shownCode(at: ordinal)?.text ?? transcript.contentText(at: ordinal))
    }
}
