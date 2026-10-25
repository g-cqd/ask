/// One key of a definition file's head, with the key spelled as it was written.
public struct DefinitionEntry: Sendable, Equatable {
    public let key: String
    public let value: DefinitionValue
    /// The key by meaning, worked out once: every lookup compares these.
    let canonical: String

    public init(key: String, value: DefinitionValue) {
        self.key = key
        self.value = value
        canonical = key.canonicalKey
    }
}
