internal import TerminalKitText

/// A drag held at the top or bottom edge of the transcript, and where the pointer is.
///
/// Terminals report no motion while a button is held still, so scrolling that depends on motion stops when the hand does. The host
/// keeps a timer while `request` is set and calls `ScreenController.tick()`; this records what that call needs.
struct DragAutoscroll: Sendable, Equatable {
    /// How often the host ticks while a drag is held at an edge: about twenty lines a second.
    static let interval = Duration.milliseconds(50)

    /// Which edge the pointer is at, or nil when it is inside the content.
    var request: ScrollRequest?
    /// The last cell the drag reached, whose row is the edge.
    var row = 0
    var col = 0
    /// The scroll position at which the selection was last extended to the pointer, so the line scrolled into view is not missed.
    var extendedAt = 0
}
