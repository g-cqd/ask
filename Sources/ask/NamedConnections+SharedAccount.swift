internal import AskAI
internal import Foundation

extension NamedConnections {
    /// After a sign-in, says when the account is one another sign-in already holds. A notice only: it never fails a sign-in, and
    /// anything it cannot read it leaves out.
    /// - Parameters:
    ///   - identity: the account just signed in.
    ///   - connection: the named connection signed in, or nil for the default sign-in.
    static func reportSharedAccount(_ identity: AccountIdentity, connection: ConnectionRecord?) {
        let others = (try? registry().connections(as: identity, excluding: connection)) ?? []
        // The default sign-in counts as another holder only when this was a named sign-in.
        let defaultHolds = connection != nil && ((try? CredentialFile.standard().isSignedIn(as: identity)) ?? false)
        if let notice = AccountSharing(connections: others, defaultSignIn: defaultHolds).notice { report([notice]) }
    }
}
