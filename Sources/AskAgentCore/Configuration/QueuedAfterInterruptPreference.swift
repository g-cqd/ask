/// What happens to the messages queued behind a turn the person interrupted (`ui.interruptSendsQueued`, roadmap 0083).
public enum QueuedAfterInterruptPreference: String, Sendable, CaseIterable {
    /// They go back to the input to be edited.
    case none
    /// The next one starts a turn; the others wait their turn, one per turn.
    case next
    /// The first starts a turn and the others join it as steering.
    case all
}
