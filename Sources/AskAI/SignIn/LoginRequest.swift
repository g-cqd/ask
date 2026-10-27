/// What `ask login` and `/login` were asked for, read from words so both say it the same way: `claude`, `claude api-key`, `codex device`,
/// `openrouter`, `custom NAME URL`, `claude --name work`.
public struct LoginRequest: Sendable, Equatable {
    /// How to sign in, when the provider offers more than one way.
    public enum Method: String, Sendable, Equatable {
        /// The provider's own account, in a browser.
        case account
        /// An API key, typed or pasted.
        case apiKey = "api-key"
        /// A code typed at a link, for a machine with no browser.
        case device
    }

    /// The providers with a sign-in of their own; anything else that has a key preset is signed in with its key.
    public static let accounts = ["claude", "codex", "agy", "spettro", "mistral-vibe", CopilotProtocol.name]

    public let target: String
    public var method: Method?
    /// A named connection to register for `claude` or `codex`, apart from the default account.
    public var connection: String?
    /// For `custom`: the endpoint's name and address.
    public var endpointName: String?
    public var endpointURL: String?
    public var replaceAccount = false

    /// A request for `target`.
    public init(target: String, method: Method? = nil) {
        self.target = target
        self.method = method
    }

    /// Why the words are not a request.
    public struct Invalid: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    /// Reads `words`, the arguments of `/login`; an empty list is `claude`, as `ask login` is.
    /// - Throws: ``Invalid`` saying what was wrong.
    public init(words: [String]) throws(Invalid) {
        var rest = words[...]
        let target = rest.popFirst() ?? "claude"
        self.init(target: target == "anthropic" ? "claude" : target)
        while let word = rest.popFirst() {
            switch word {
                case "api-key", "--api-key": method = .apiKey
                case "device", "--device": method = .device
                case "account": method = .account
                case "--replace-account": replaceAccount = true
                case "--name":
                    guard let value = rest.popFirst() else { throw Invalid(description: "--name needs a name") }
                    connection = value
                default:
                    guard self.target == "custom" else { throw Invalid(description: "unexpected \"\(word)\"") }
                    if endpointName == nil {
                        endpointName = word
                    } else if endpointURL == nil {
                        endpointURL = word
                    } else {
                        throw Invalid(description: "unexpected \"\(word)\"")
                    }
            }
        }
        try check()
    }

    private func check() throws(Invalid) {
        let known = Self.accounts + ["custom", "openai"] + ProviderPreset.all.map(\.name)
        guard known.contains(target) else { throw Invalid(description: "no sign-in called \"\(target)\"") }
        if connection != nil, !["claude", "codex"].contains(target) || method == .apiKey {
            throw Invalid(description: "a named connection is a claude or codex account, not a key")
        }
        if method == .device, !["codex", CopilotProtocol.name].contains(target) {
            throw Invalid(description: "device sign-in is for codex or copilot-vscode")
        }
        if method == .apiKey,
            !(["claude", "codex", "openai", "custom"] + ProviderPreset.all.map(\.name)).contains(target)
        {
            throw Invalid(description: "\(target) signs in with its account, not a key")
        }
    }

    /// The name the key is stored under, and the provider it opens: Claude's key is Anthropic's, and Codex's API key is OpenAI's.
    public var keyProvider: String? {
        switch target {
            case "claude": ProviderSettings.anthropic
            case "codex", "openai": "openai"
            case "custom": endpointName?.lowercased()
            case "agy", "spettro", "mistral-vibe", CopilotProtocol.name: nil
            default: target
        }
    }

    /// Whether this signs in with a key the person supplies.
    public var usesTypedKey: Bool {
        if method == .apiKey { return true }
        return !(Self.accounts.contains(target))
    }
}
