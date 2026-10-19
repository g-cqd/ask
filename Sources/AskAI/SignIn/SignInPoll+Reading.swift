extension SignInPoll {
    /// Reads a poll answer in the shape both sign-ins use: a status, and a secret once the status says it is done.
    ///
    /// Anything not named is refused rather than guessed at, so a server that adds a state cannot be mistaken for
    /// success; and a secret is accepted only if it is fit to store and to put in a header.
    /// - Parameters:
    ///   - status: the answer's `status` field.
    ///   - secret: the field that carries the secret once complete.
    ///   - complete: the status word that means the user finished.
    ///   - secretField: the secret's field name, for the error.
    ///   - ending: the statuses that end the sign-in, and why.
    /// - Returns: ``SignInPoll/pending``, or ``SignInPoll/complete(_:)`` with the secret.
    /// - Throws: the reason in `ending` for a status that ends the sign-in, else ``SignInError/invalidResponse(_:)``
    ///   for a status not named or a secret not fit to use.
    static func reading(
        status: String?, secret: String?, complete: String, secretField: String, ending: [String: SignInError]
    ) throws(SignInError) -> SignInPoll {
        if status == "pending" { return .pending }
        if let status, let reason = ending[status] { throw reason }
        guard status == complete else { throw .invalidResponse("status") }
        guard SignInSecret.isValid(secret), let secret else { throw .invalidResponse(secretField) }
        return .complete(secret)
    }
}
