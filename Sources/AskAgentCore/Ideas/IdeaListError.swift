/// Why a change to the ideas was refused; they are left as they were.
public enum IdeaListError: Error, Equatable, Sendable {
    case unknownIdea(Int)
    case emptyText
    /// A new idea with an id given before.
    case taken(Int)
    /// A batch inside a batch: never written, refused when read.
    case nested
}
