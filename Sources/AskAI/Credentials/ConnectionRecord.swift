public import Foundation

/// Nonsecret registration metadata. Names can change; ids and the on-disk location do not.
public struct ConnectionRecord: Codable, Sendable, Equatable {
    internal var schemaVersion: Int? = 1
    public let id: UUID
    public internal(set) var name: String
    public let provider: ConnectionKind
    /// Changes when authentication is removed or a different account replaces it; old runs must not follow it silently.
    public internal(set) var authorizationID: UUID
    internal var accountIdentity: String?
    internal var removed = false
    internal var authenticatedBefore = false

    internal init(name: String, provider: ConnectionKind) {
        id = UUID()
        self.name = name
        self.provider = provider
        authorizationID = UUID()
    }

    /// A lower-case CLI name, never a path. Existing configured names are checked separately for collisions.
    public static func canonical(_ name: String) -> String? {
        let value = name.lowercased()
        return PlainToken.word(value, length: 1 ... 64, lowercase: true) ? value : nil
    }
}
