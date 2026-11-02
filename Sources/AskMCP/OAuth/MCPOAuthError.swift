/// Why a server could not be authorized: discovery found nothing or something the specification forbids, or a step was refused.
public struct MCPOAuthError: Error, Sendable, Equatable, CustomStringConvertible {
    /// In words, never with a secret in it.
    public let reason: String

    public init(_ reason: String) { self.reason = reason }

    public var description: String { reason }
}
