/// One change to the ideas, as it is kept (ADR-0140, roadmap 0180).
public enum IdeaChange: Codable, Equatable, Sendable {
    case add(Idea)
    case edit(id: Int, text: String, at: Int)
    case state(id: Int, IdeaState)
}
