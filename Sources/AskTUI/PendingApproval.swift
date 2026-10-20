/// An approval question waiting for the user's answer.
public struct PendingApproval: Sendable, Equatable {
    /// Which question it is, so the answer reaches the call that asked.
    public let id: Int
    public let question: String
}
