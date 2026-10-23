internal import TerminalKitInput

/// Everything the screen's loop reacts to, merged into one stream so state has a single owner.
enum ScreenEvent: Sendable {
    case input(InputEvent)
    case update(ConversationUpdate)
    case resize
    /// A timer step while a drag is held at an edge of the transcript.
    case tick
    case inputEnded
}
