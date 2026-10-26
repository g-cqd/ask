internal import AskAI
internal import Foundation

/// Forgets what was signed in: one account, or all of them. Shared by `ask logout` and `/logout`, so either can sign out anything the other can.
struct AccountLogout {
    /// Why nothing could be forgotten.
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let environment: [String: String]

    /// Forgets `target`, or everything when nil.
    /// - Returns: what was done, in a sentence.
    /// - Throws: the credential store's or the registry's error, or a ``Failure`` for a name that is nothing signed in.
    func run(_ target: String?) throws -> String {
        let file = CredentialFile.standard(environment: environment)
        guard let target else {
            try file.remove()
            let listing = try NamedConnections.registry(environment: environment).list()
            NamedConnections.report(listing.notices)
            for record in listing.records { try NamedConnections.registry(environment: environment).signOut(record) }
            if !listing.notices.isEmpty {
                throw Failure(
                    description:
                        "readable connections were signed out, but unreadable registrations could not be changed; see the notices above"
                )
            }
            return "Signed out of everything."
        }
        let named = ConnectionRecord.canonical(target)
        let isNamed = try named.map { name in
            try NamedConnections.registry(environment: environment).list().records.contains { $0.name == name }
        }
        if isNamed == true, LoginTarget.builtIn(target) == false {
            try NamedConnections.registry(environment: environment)
                .signOut(NamedConnections.named(target, environment: environment))
            return "Signed out of connection \(target)."
        }
        guard try file.signOut(target: target) else { throw Failure(description: "nothing is signed in as \(target).") }
        return "Signed out of \(target)."
    }
}
