internal import TerminalKitInput

/// Everything the screen's loop reacts to, merged into one stream so state has a single owner.
enum ScreenEvent: Sendable {
    case input(InputEvent)
    case update(ConversationUpdate)
    case resize
    /// A timer step while a drag is held at an edge of the transcript.
    case tick
    /// A tick of the progress timer: `advancesFrames` when the spinners step, else a shimmer's redraw only.
    case progressTick(advancesFrames: Bool)
    /// The host pasteboard command ended: the final notice for the copy numbered `generation`, and whether it failed.
    case copied(notice: String, failed: Bool, generation: Int)
    /// A paste the terminal passed on could not read the pasteboard: why, for the transcript (roadmap 0082).
    case pasteRefused(String)
    /// The two seconds after an arming Ctrl+C are over.
    case quitWindowEnded(generation: Int)
    /// A thread's question has waited its `threads.questions` delay.
    case threadQuestionDelayEnded
    /// The sandbox note has been up for its five seconds.
    case sandboxNoteEnded(generation: Int)
    case inputEnded
    /// Time to ask the terminal for its colours again, after macOS changed appearance (roadmap 0108).
    case askColours
}
