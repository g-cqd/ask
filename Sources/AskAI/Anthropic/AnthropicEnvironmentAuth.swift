/// Which Anthropic credential the environment supplies, in pi's order among the variables: `ANTHROPIC_AUTH_TOKEN` (a bearer token
/// for a gateway), then `ANTHROPIC_OAUTH_TOKEN` (a subscription token supplied by a script), then `ANTHROPIC_API_KEY`.
///
/// An empty variable is unset, so it cannot mask a valid one below it. A variable that is set and not a plain token refuses
/// the run, and does not fall through to a lower one: sending a different credential than the one the user set is the worse failure.
public enum AnthropicEnvironmentAuth {
    /// The most characters a token may have.
    public static let lengthLimit = 4096

    /// The variables a credential is read from, in the order they are tried, each with what it makes of the value.
    private static let readers: [(variable: String, auth: @Sendable (String) -> AnthropicClient.Auth)] = [
        ("ANTHROPIC_AUTH_TOKEN", { .bearer($0) }), ("ANTHROPIC_OAUTH_TOKEN", { .subscription(accessToken: $0) }),
        ("ANTHROPIC_API_KEY", { .apiKey($0) })
    ]

    /// The names of the variables ``resolve(environment:)`` reads, so that nothing else has to say them again.
    public static var variables: [String] { readers.map(\.variable) }

    /// The credential the environment names, or nil when it names none.
    /// - Parameter environment: the process environment.
    /// - Returns: the auth to send, or nil.
    /// - Throws: ``AnthropicEnvironmentAuthError/notAToken(variable:)`` for the highest variable that is set and not plain.
    public static func resolve(environment: [String: String]) throws(AnthropicEnvironmentAuthError) -> AnthropicClient
        .Auth?
    {
        for candidate in readers {
            guard let value = environment[candidate.variable], !value.isEmpty else { continue }
            guard isPlain(value) else { throw .notAToken(variable: candidate.variable) }
            return candidate.auth(value)
        }
        return nil
    }

    /// Visible ASCII only, within the limit: no space, no control character, nothing that could end a header line.
    private static func isPlain(_ value: String) -> Bool {
        value.utf8.count <= lengthLimit && value.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7E }
    }
}
