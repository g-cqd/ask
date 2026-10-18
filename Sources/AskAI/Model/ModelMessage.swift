internal import AemiJSON

/// A message in the conversation sent to the model.
public struct ModelMessage: Sendable, Equatable {
    public enum Role: Sendable, Equatable { case user, assistant }

    public var role: Role
    public var blocks: [RequestBlock]

    /// A message from `role`.
    public init(role: Role, blocks: [RequestBlock]) {
        self.role = role
        self.blocks = blocks
    }
}
