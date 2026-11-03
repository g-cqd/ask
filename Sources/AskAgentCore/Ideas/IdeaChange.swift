/// One change to the notes, as it is kept (ADR-0140, ADR-0141).
public enum IdeaChange: Equatable, Sendable {
    case add(Idea)
    case edit(id: Int, text: String, at: Int)
    case state(id: Int, IdeaState)
    /// The note became task `task` (ADR-0141).
    case link(id: Int, task: Int)
    /// Removes note `id`.
    case remove(id: Int)
    /// A call's changes, kept or lost together; never nested.
    indirect case batch([IdeaChange])
}
