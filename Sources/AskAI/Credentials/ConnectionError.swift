/// Registration errors contain names and paths, never credentials or remote account identities.
public enum ConnectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidName
    case nameInUse(String)
    case notFound(String)
    case changed(String)
    case replacementRequired(String)
    case unreadableRegistry(String)
    case signInRequired(name: String, provider: ConnectionKind)

    public var description: String {
        switch self {
            case .signInRequired(let name, let provider):
                "connection '\(name)' is signed out: run `ask login \(provider == .codex ? "codex" : "claude") --name \(name)`"
            // @dl:accept -- diagnostic sentences are independent data, not repair logic shared with session logs
            case .invalidName:
                "a connection name needs 1–64 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit"
            // @dl:accept -- diagnostic sentences are independent data, not shared with sign-in errors
            case .nameInUse(let name):
                "connection name '\(name)' already belongs to another destination; choose another name"
            // @dl:accept -- diagnostic sentences are independent data, not shared with credential-file errors
            case .notFound(let name): "no connection is named '\(name)'; run `ask connections`"
            case .changed(let name):
                "connection '\(name)' changed or was removed while this operation was waiting; select it again explicitly"
            case .unreadableRegistry(let detail):
                "cannot prove a connection name is unused while registrations are unreadable: \(detail)"
            case .replacementRequired(let name):
                "sign-in would replace the account for '\(name)'; use --replace-account to authorize that change"
        }
    }
}
