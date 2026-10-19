/// A ``BrowserSignIn`` that ends in an API key, which is stored as one.
public protocol KeySignIn: BrowserSignIn where Grant == String, Outcome == StoredKey {
    /// The time to record on the key, in seconds since 1970.
    func timestamp() -> Double
}

extension KeySignIn {
    /// Flows whose poll hands over the key itself need nothing more.
    public func finish(_ session: Session, grant: String) async throws(SignInError) -> StoredKey {
        StoredKey(key: grant, obtainedAt: timestamp())
    }
}
