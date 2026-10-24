internal import TerminalKitText

/// What the last frame drew, as a mouse event needs it: which content each transcript row shows, and how big the transcript was.
struct FrameGeometry: Sendable {
    /// What each row of the screen shows, for mapping a cell back to the conversation.
    var rows = RowMap<Int>()
    /// How many rows the transcript took, from the top.
    var transcriptRows = 0
    var columns = 0
    /// How many wrapped lines the whole transcript has, so a scroll can stop at the top.
    var totalLines = 0
    /// The scroll position this frame was drawn at. A timer step waits until the frame it sees matches the position it asked for.
    var scrollback = 0
    /// The status line's row, and the columns its runner count covers, so a click on the count opens the list.
    var statusRow = 0
    var runnerColumns: Range<Int>?
    /// The picker's matches as drawn: the row of the first, which matches they are, and the word they were for, so a click on a row
    /// means the match the user saw, and means nothing if the list has since moved on.
    var pickerFirstRow = 0
    var pickerWindow = 0 ..< 0
    var pickerTrigger: CompletionTrigger?
    /// The input as drawn: its first screen row, how many rows, the draft's display row at the top, and the map from cell to text.
    var promptRow = 0
    var promptRows = 0
    var promptTop = 0
    var prompt: InputLayout?
}
