/// A command's choices as the screen holds them: the rows, and when they arrived, so an old list is asked for again when it next opens.
struct ChoiceList: Sendable, Equatable {
    let rows: [ChoiceRow]
    let at: ContinuousClock.Instant
    /// Whether something that can change the list has happened since it arrived: it is still shown, and asked for again.
    var stale = false
}
