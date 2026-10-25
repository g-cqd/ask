/// The main conversation, set aside while a runner's output has the transcript. Leaving the lane puts it back exactly: its items, folds and scroll position.
struct LaneView: Sendable, Equatable {
    /// The runner shown.
    var id: String
    /// What the status line calls it.
    var name: String
    var stashed: Transcript
    var stashedScrollback: Int
}
