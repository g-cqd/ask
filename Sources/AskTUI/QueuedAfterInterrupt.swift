/// What happens to the messages queued behind an interrupted turn (`ui.interruptSendsQueued`).
public enum QueuedAfterInterrupt: String, Sendable {
    case none
    case next
    case all
}
