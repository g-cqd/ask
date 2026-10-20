/// Why an alias cannot be made, read or used. Each case says what to change; none carries a credential.
public enum ModelAliasError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidName
    case invalidModel
    case invalidLimit
    case selfReference(String)
    case shadowsModel(String)
    case tooMany
    case chained(String)
    case ambiguous(String)
    case notFound(String)
    case isDefault(String)
    case damaged(path: String)
    case newerFormat(path: String)
    case locked(path: String)
    case io(path: String, errno: Int32)

    // @dl:accept -- diagnostic sentences are independent data, like every error enum's description
    public var description: String {
        switch self {
            case .invalidName:
                "an alias is 1-64 lower-case letters, digits, dots, underscores or hyphens, starting with a letter or digit"
            case .invalidModel:
                "a model id is 1-128 letters, digits, dots, underscores or hyphens, starting with a letter or digit"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .invalidLimit: "a stated limit must be a positive whole number"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .selfReference(let name): "alias '\(name)' names itself; give it the server's model id"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .shadowsModel(let name): "'\(name)' is already a model on this account, so it cannot also be an alias"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .tooMany: "a connection keeps at most 64 aliases"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .chained(let name): "alias '\(name)' points at another alias; point it at the server's model id"
            case .ambiguous(let name):
                "'\(name)' is both an alias and a model on this account; remove the alias or name the model another way"
            case .isDefault(let name): "alias '\(name)' is the default model; clear the default first"
            case .notFound(let name): "there is no alias named '\(name)'"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .damaged(let path): "\(path) is not a valid alias file; repair it or remove it"
            // @dl:accept -- diagnostic sentences are independent data, not logic shared with other error enums
            case .newerFormat(let path): "\(path) was written by a newer ask; update ask before changing it"
            case .locked(let path): "another ask is changing \(path); try again"
            case .io(let path, let code): "\(path): error \(code)"
        }
    }
}
