internal import TerminalKitText

/// What the last frame drew, as a mouse event needs it: which content each transcript row shows, and how big the transcript was.
struct FrameGeometry: Sendable {
    /// What each row of the screen shows, for mapping a cell back to the conversation.
    var rows = RowMap<Int>()
    /// Foldable block owning each transcript row, including its padding but not inter-block spacing.
    var foldBlocks: [Int?] = []
    /// The links each transcript row draws, so a click on one opens it.
    var links: [[PathLinks.Link]] = []
    /// How many rows the transcript took, from the top.
    var transcriptRows = 0
    var columns = 0
    /// The width the transcript is wrapped and drawn in: less than `columns` when the sidebar takes the right of it.
    var transcriptColumns = 0
    /// The runner each row of the sidebar shows, from the top; its first column is `transcriptColumns + 1`.
    var sidebarIDs: [String] = []
    /// How many wrapped lines the whole transcript has, so a scroll can stop at the top.
    var totalLines = 0
    /// The scroll position this frame was drawn at. A timer step waits until the frame it sees matches the position it asked for.
    var scrollback = 0
    /// The status line's row, and the columns its runner count covers, so a click on the count opens the list.
    var statusRow = 0
    var runnerColumns: Range<Int>?
    /// The columns of "N lines below" in the status line, when it is there, so a click on it goes to the end.
    var belowColumns: Range<Int>?
    /// The columns of the idle mark in the status line, when it is the mark, so a click on it names the sandbox state.
    var markColumns: Range<Int>?
    /// The picker's matches as drawn: the row of the first, which matches they are, and the word they were for, so a click on a row
    /// means the match the user saw, and means nothing if the list has since moved on.
    var pickerFirstRow = 0
    /// The screen rows of the approval section's answers, first answer first, so a click on one checks it (roadmap 0116).
    var approvalAnswers = 0 ..< 0
    /// The screen rows of the approval's command, which a click unfolds (roadmap 0157).
    var approvalDetail = 0 ..< 0
    /// The columns of the model's questions' tabs, on the ``approvalDetail`` row, the review last (roadmap 0117).
    var questionTabs: [Range<Int>] = []
    var pickerWindow = 0 ..< 0
    var pickerTrigger: CompletionTrigger?
    /// The strip's rows as drawn: the screen row of the first, and the runner each shows, so a click means what the user saw.
    var stripFirstRow = 0
    var stripIDs: [String] = []
    /// The input as drawn: its first screen row, how many rows, the draft's display row at the top, and the map from cell to text.
    var promptRow = 0
    var promptRows = 0
    var promptTop = 0
    var prompt: InputLayout?
}
