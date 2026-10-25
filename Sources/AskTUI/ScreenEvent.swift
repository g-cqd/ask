internal import TerminalKitInput

/// Everything the screen's loop reacts to, merged into one stream so state has a single owner.
enum ScreenEvent: Sendable {
    case input(InputEvent)
    case update(ConversationUpdate)
    case resize
    /// A timer step while a drag is held at an edge of the transcript.
    case tick
    /// The host pasteboard command ended: the final notice for the copy numbered `generation`, and whether it failed.
    case copied(notice: String, failed: Bool, generation: Int)
    /// The two seconds after an arming Ctrl+C are over.
    case quitWindowEnded(generation: Int)
    case inputEnded
}
