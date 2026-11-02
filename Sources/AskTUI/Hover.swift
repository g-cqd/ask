/// What the pointer is over, of what a click acts on (roadmap 0172): kept as the thing, not a screen row, so a scroll or new output
/// never leaves another row lit.
enum Hover: Sendable, Equatable {
    /// A foldable block of the transcript, by its item: its header brightens.
    case block(Int)
    /// A row of the job list below the input, by its id.
    case job(String)
}
