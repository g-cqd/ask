/// A user message waiting for a safe boundary, identified so a front end acknowledges it only after persistence.
public struct QueuedPrompt: Sendable, Equatable {
    /// When the message may enter the conversation.
    public enum Delivery: Sendable {
        /// After the current response and all its tools have finished.
        case steering
        /// After the agent has finished its pending work.
        case followUp
    }

    public let id: Int
    public let text: String
    public let delivery: Delivery

    /// A pending message. Identifiers must be unique within a run.
    public init(id: Int, text: String, delivery: Delivery = .steering) {
        self.id = id
        self.text = text
        self.delivery = delivery
    }
}
