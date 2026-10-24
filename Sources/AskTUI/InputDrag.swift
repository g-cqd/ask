internal import TerminalKitInput
internal import TerminalKitText

/// A drag that selects text in the input: where it began, where it is, and which edge it is held at.
///
/// Positions are character offsets in the draft, each with the offset after its character, so a drag includes the character under
/// the pointer at both ends, in either direction, as the transcript's selection does. Motion inside the cell that was pressed selects
/// nothing.
struct InputDrag: Sendable, Equatable {
    var isActive = false
    var anchorBefore = 0
    var anchorAfter = 0
    var headBefore = 0
    var headAfter = 0
    /// The cell that was pressed, until the pointer leaves it.
    var press: CellPosition?
    /// The edge the pointer is at while more rows lie that way, for the timer.
    var request: ScrollRequest?
    /// The column the head keeps while the timer steps it a row at a time.
    var column = 0

    /// What is selected: from the press to the head. It is only asked once the pointer has left the pressed cell.
    var range: Range<Int>? {
        guard isActive else { return nil }
        let range =
            isForward
            ? anchorBefore ..< Swift.max(headAfter, anchorBefore) : headBefore ..< Swift.max(anchorAfter, headBefore)
        return range.isEmpty ? nil : range
    }

    private var isForward: Bool { headBefore >= anchorBefore }

    /// Where the cursor goes: the head's end of the selection.
    var cursor: Int { isForward ? Swift.max(headAfter, anchorBefore) : headBefore }
}
