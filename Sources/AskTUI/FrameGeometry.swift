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
}
