/// How far a long call has got, as the server reported it.
public struct MCPProgress: Sendable, Equatable {
    /// How much is done, in the server's own unit.
    public let progress: Double
    /// How much there will be, if the server knows.
    public let total: Double?
    /// A word about what is happening.
    public let message: String?

    /// A report of `progress`.
    public init(progress: Double, total: Double?, message: String?) {
        self.progress = progress
        self.total = total
        self.message = message
    }
}
