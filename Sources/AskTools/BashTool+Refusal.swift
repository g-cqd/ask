internal import AskAI
internal import AskAgentCore

/// What the check before a command refuses (roadmap 0188, the owner's choices of 2026-11-02): a command that does not parse, always; one
/// shellcheck finds fault with, once, so the model reads the findings at once rather than waiting on the command, and runs it as written by
/// sending it again.
extension BashTool {
    /// What a command run without its check finishing says.
    static let uncheckedNote = "[not checked: the shell's parse or shellcheck took more than its deadline]"

    /// `result` with what the check found: shellcheck's findings on a failure, and a note when the command ran unchecked.
    static func annotate(_ result: inout ToolOutput, _ checked: CommandCheck.Result) {
        if result.isError, !checked.findings.isEmpty {
            result.content += "\n[shellcheck] " + checked.findings.joined(separator: "\n[shellcheck] ")
        }
        if checked.unchecked { result.content += "\n" + uncheckedNote }
    }

    /// Throws when `checked` refuses `command`.
    func refuse(_ command: String, shell: String, _ checked: CommandCheck.Result) throws(ToolFailure) {
        if let syntaxError = checked.syntaxError {
            throw ToolFailure("The command does not parse in \(shell), so it was not run:\n\(syntaxError)")
        }
        guard checked.findings.contains(where: CommandCheck.refuses), refused.refuses(command, shell: shell) else {
            return
        }
        throw ToolFailure(
            "shellcheck found this in the command, so it was not run:\n[shellcheck] "
                + checked.findings.joined(separator: "\n[shellcheck] ")
                + "\nFix it, or send the same command again to run it as written."
        )
    }
}
