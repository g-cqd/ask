internal import AemiJSON
internal import AskAgentCore

/// What bounds one script (ADR-0156): the limits are the design, and each is a failure that says why, never a silent cut.
struct CodemodeLimits: Sendable, Equatable {
    /// The longest a script may ask to run: what `bash` allows a command.
    static let maximumDeadline: Duration = .seconds(600)
    /// The most a script may ask to have returned, in tokens.
    static let maximumOutputTokens = 100_000

    /// How long the script may run before it is stopped.
    var deadline: Duration = .seconds(120)
    /// How much of what it said goes back to the model, in tokens of about four bytes; the rest is in a file.
    var outputTokens = 10_000
    /// What the process that runs it may take of memory before it ends itself.
    var memoryMiB = 256
    /// How many of its tool calls run at once; the others wait their turn.
    var callsInFlight = 16

    /// The limits for `code`: ask's, with what its first line sets (`// @options: {"timeout_ms": …, "max_output_tokens": …}`).
    static func parse(_ code: String) -> Result<CodemodeLimits, ToolFailure> {
        var limits = CodemodeLimits()
        let first = code.prefix { !$0.isNewline }.drop { $0 == " " || $0 == "\t" }
        guard first.hasPrefix("//") else { return .success(limits) }
        let comment = first.dropFirst(2).drop { $0 == " " }
        guard comment.hasPrefix("@options:") else { return .success(limits) }
        let json = Array(comment.dropFirst("@options:".count).utf8)
        guard let options = (try? AemiJSON.parse(json))?.root.object else {
            return .failure(ToolFailure("The options on the first line are not a JSON object."))
        }
        for (name, value) in options {
            switch name {
                case "timeout_ms":
                    let most = Int(maximumDeadline.components.seconds) * 1000
                    guard let milliseconds = value.int, (1 ... most).contains(milliseconds) else {
                        return .failure(ToolFailure("timeout_ms must be between 1 and \(most)."))
                    }
                    limits.deadline = .milliseconds(milliseconds)
                case "max_output_tokens":
                    guard let tokens = value.int, (1 ... maximumOutputTokens).contains(tokens) else {
                        return .failure(ToolFailure("max_output_tokens must be between 1 and \(maximumOutputTokens)."))
                    }
                    limits.outputTokens = tokens
                default:
                    return .failure(ToolFailure("\(name) is not an option: timeout_ms and max_output_tokens are."))
            }
        }
        return .success(limits)
    }
}
