/// The destination a request was sent to, independent of its display name and without credentials or account email.
public struct SessionDestination: Codable, Sendable, Equatable {
    public let connectionID: String
    public let authorizationID: String?
    public let name: String
    public let model: String

    /// A stable connection identity, its selected authorization revision, and the raw model id.
    public init(connectionID: String, authorizationID: String?, name: String, model: String) {
        self.connectionID = connectionID
        self.authorizationID = authorizationID
        self.name = name
        self.model = model
    }

    /// The prefix of a destination that is an unnamed provider: what every session before named connections used.
    public static let providerPrefix = "provider:"

    /// Whether this is anything but an unnamed provider. Unknown shapes count as named, which is the stricter reading.
    public var isNamed: Bool { !connectionID.hasPrefix(Self.providerPrefix) }

    /// Checks consent before history is sent to a destination; changing only a model or local label is not rerouting.
    /// - Throws: a ``SessionDestinationError`` if existing history would move without explicit user selection.
    public func check(replacing previous: SessionDestination?, hasHistory: Bool, explicitlySelected: Bool)
        throws(SessionDestinationError)
    {
        guard hasHistory, !explicitlySelected else { return }
        guard let previous else {
            // History from before named connections went to an unnamed provider; it may continue on one.
            if isNamed { throw .unbound }
            return
        }
        guard connectionID == previous.connectionID, authorizationID == previous.authorizationID else { throw .changed }
    }
}
