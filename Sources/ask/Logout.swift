internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask logout`: forget stored credentials, one provider's or all.
struct Logout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Forget stored credentials.")

    @Argument(help: "Forget only this sign-in. Default: all of them.") var provider: String?

    func run() throws {
        let file = CredentialFile.standard(environment: LaunchEnvironment.values)
        do {
            if let name = provider {
                if let target = LoginTarget(rawValue: name) {
                    switch target {
                        case .claude: try file.removeClaude()
                        case .codex: try file.removeCodex()
                        case .agy: try file.removeAgy()
                        default: try target.keyName.map { try file.removeKey(for: $0) }
                    }
                } else {
                    try NamedConnections.registry().signOut(NamedConnections.named(name))
                }
            } else {
                try file.remove()
                let listing = try NamedConnections.registry().list()
                NamedConnections.report(listing.notices)
                for record in listing.records { try NamedConnections.registry().signOut(record) }
                if !listing.notices.isEmpty {
                    fail(
                        "ask: readable connections were signed out, but unreadable registrations could not be changed; see the notices above",
                        code: 78)
                }
            }
        } catch { fail("ask: \(error)", code: 78) }
        print("Signed out.")
    }
}
