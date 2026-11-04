/// The main conversation, set aside while a runner's output has the transcript. Leaving the lane puts it back exactly: its items, folds and scroll position.
struct LaneView: Sendable, Equatable {
    /// The runner shown.
    var id: String
    /// What the status line calls it.
    var name: String
    var stashed: Transcript
    var stashedScrollback: Int
    /// Whether the runner is a thread (roadmap 0194): its own conversation is shown, and the input talks to it.
    var isThread = false
    /// In a thread's lane, main's own questions wait here, since the section shows the thread's (roadmap 0195).
    var stashedApproval: PendingApproval?
    var stashedQuestions: PendingQuestions?
}
