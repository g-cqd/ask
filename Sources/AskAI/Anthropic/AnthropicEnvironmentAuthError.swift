/// Why the Anthropic credentials in the environment cannot be used. The message names the variable, never its value.
public enum AnthropicEnvironmentAuthError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The variable holds something that is not a plain token: a space, a control character, a non-ASCII character, or too much.
    case notAToken(variable: String)

    public var description: String {
        switch self {
            case .notAToken(let variable):
                "\(variable) is not a plain token (it has a space, a control character or a character outside ASCII, or is too long); fix or unset it"
        }
    }
}
