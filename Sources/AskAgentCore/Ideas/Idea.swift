/// One idea (roadmap 0180), kept exactly as the person typed it.
public struct Idea: Codable, Sendable, Equatable {
    /// `i1`, `i2`, … in the order had; never reused.
    public let id: Int
    public var text: String
    /// When it was had, in seconds since 1970.
    public let made: Int
    /// When the person last edited it.
    public var edited: Int?
    public var state: IdeaState

    public var name: String { "i\(id)" }
}
