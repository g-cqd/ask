/// The commands typed during a turn that the screen keeps track of (roadmap 0113): those waiting for its end, and those running beside
/// it, whose question to the person must outlive the turn.
struct TurnCommands: Sendable, Equatable {
    /// A command waiting for the turn's end, shown as waiting at `transcriptIndex`.
    struct Waiting: Sendable, Equatable {
        let line: String
        let name: String
        let arguments: String
        let transcriptIndex: Int
    }

    /// In the order they were typed.
    var waiting: [Waiting] = []
    /// How many commands run beside the screen's run now.
    var besideRunning = 0
    /// The question a command beside the run asked, which the run's end leaves alone.
    var besideInputID: Int?
}
