internal import AskAI

/// A sign-in without `--name` to a provider already signed in with another account: kept beside it, never in its place (roadmap 0092).
extension AccountLogin {
    /// Where a sign-in went and what to tell the person about it.
    struct Placement {
        /// The named connection it is stored in; nil for the default sign-in.
        let connection: ConnectionRecord?
        /// A sentence to add to the sign-in's line, when it did not go to the default.
        let note: String
    }

    /// The configured names a new connection must not take.
    var reservedNames: [String] { (try? NamedConnections.reserved()) ?? [] }

    /// Stores `signIn` in the connection `named`, else where ``ConnectionRegistry/storeSignIn(_:defaultFile:replace:reserved:)`` puts it.
    func store(_ signIn: SubscriptionSignIn, named: ConnectionRecord?, file: CredentialFile, replace: Bool) throws
        -> Placement
    {
        let registry = NamedConnections.registry(environment: environment)
        guard let named else {
            return try described(
                registry.storeSignIn(signIn, defaultFile: file, replace: replace, reserved: reservedNames), in: registry
            )
        }
        try registry.save(signIn, for: named, replaceAccount: replace)
        return Placement(connection: named, note: "")
    }

    /// What the person is told of `placement`, with the connection it names.
    func described(_ placement: SignInPlacement, in registry: ConnectionRegistry) throws -> Placement {
        switch placement {
            case .defaultSignIn: return Placement(connection: nil, note: "")
            case .connection(let name):
                return Placement(
                    connection: try registry.list().records.first { $0.name == name },
                    note: " It is the account of the connection \(name), which now uses this sign-in.")
            case .newConnection(let name):
                return Placement(
                    connection: try registry.list().records.first { $0.name == name },
                    note: """
                         It is another account than the default's, so it was added as the connection \(name), and the default is \
                        unchanged. Choose it with /model or --provider \(name); rename it with `ask connections rename \(name) NEW`; \
                        sign in with --replace-account to replace the default instead.
                        """)
        }
    }
}
