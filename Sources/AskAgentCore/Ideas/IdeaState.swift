/// Where an idea stands (roadmap 0180): new until the model or the person marks it.
public enum IdeaState: String, Codable, Sendable, CaseIterable {
    case new
    case acknowledged
    case fulfilled
    case dismissed

    /// Fulfilled and dismissed ideas are shown only on request.
    public var isOpen: Bool { self == .new || self == .acknowledged }
}
