/// One model as one account lists it, for `/model`.
public struct ModelOffer: Sendable, Equatable {
    /// The name `/model` reaches the account by: a provider's, or a named connection's.
    public let account: String
    /// The subscription the account is, whose other accounts may serve the same model; nil for a provider reached with a key.
    public let kind: ConnectionKind?
    /// The server's model id.
    public let model: String

    /// An offer of `model` by `account`.
    public init(account: String, kind: ConnectionKind?, model: String) {
        self.account = account
        self.kind = kind
        self.model = model
    }
}
