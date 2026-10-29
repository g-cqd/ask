internal import AskAI
internal import Foundation
internal import Synchronization

/// Puts keys and tokens where `credentials` says (roadmap 0110), once per process and again whenever the choice changes: ask's own
/// credential file and every named connection's. A Keychain that refuses leaves everything where it was and says so; nothing is lost,
/// since an item is read back before the file lets go of its secret.
enum CredentialPlacement {
    private static let settled = Mutex<CredentialStorage?>(nil)

    /// Makes `choice` the process's and moves what is stored to match.
    /// - Returns: notices for the person: a file whose secrets could not be moved, and why.
    static func apply(_ choice: CredentialStorage, environment: [String: String]) -> [String] {
        CredentialStorage.choose(choice)
        let changed = settled.withLock { previous in
            defer { previous = choice }
            return previous != choice
        }
        guard changed else { return [] }
        // auto in an unsigned build moves nothing: secrets already in the Keychain stay there (see `CredentialFile.preferred`), and
        // secrets in the file stay there until a signed build runs.
        if choice == .auto, !CredentialStorage.runningBuildIsStablySigned { return [] }
        let registry = NamedConnections.registry(environment: environment)
        let named = ((try? registry.list())?.records ?? []).map { registry.credentials(for: $0) }
        var notices: [String] = []
        for file in [CredentialFile.standard(environment: environment)] + named {
            do { try file.settleSecrets() } catch {
                notices.append("Credentials in \(file.url.path) stay where they were: \(error)")
            }
        }
        return notices
    }
}
