internal import TerminalKitCodecs
internal import TerminalKitInput

/// A submitted line: a prompt, a command, or a command that does not exist.
extension ScreenController {
    /// A prompt of the session being shown again (a resume): in the conversation, and in the history Up browses (roadmap 0111).
    mutating func replayPrompt(_ text: String) {
        state.transcript.addUser(text)
        history.record(text)
    }

    mutating func submit(_ line: String, followUp: Bool) -> [Effect] {
        leaveLane()
        history.record(line)
        switch SlashInput(line) {
            case .prompt(let text):
                return submitPrompt(Self.isContinueWord(text) ? Self.continueText : text, followUp: followUp)
            case .command(let name, let arguments):
                state.transcript.addUser(line)
                guard let command = SlashCommand.named(name, in: commands) else {
                    state.transcript.addNotice("There is no command /\(name); /help lists them.", isError: true)
                    return []
                }
                switch command.name {
                    case "help":
                        let help = commands.map { "/\($0.name)  \($0.summary)" }.joined(separator: "\n")
                        state.transcript.addNotice(help, isError: false)
                        return []
                    case "quit": return [.quit]
                    case "jobs": return toggleRunners(announcing: true)
                    case "sidebar": return toggleSidebar(announcing: true)
                    case "verbose": return toggleVerbose()
                    case "follow-up": return submitPrompt(arguments, followUp: true)
                    case "continue": return submitPrompt(Self.continueText(with: arguments), followUp: followUp)
                    default:
                        // A list known to be empty has nothing to open: the bare command runs and says why.
                        let knownEmpty = state.choices[command.name].map { $0.rows.isEmpty && !$0.stale } ?? false
                        if command.takesChoices, arguments.isEmpty, !knownEmpty {
                            state.editor.paste("/\(command.name) ")
                            pickerScreenRows = Swift.max(pickerScreenRows, Self.pickerMinimumRows)
                            return refreshPicker(screenRows: pickerScreenRows, at: .now)
                        }
                        guard !busy() else { return [] }
                        return begin(.runCommand(name: command.name, arguments: arguments))
                }
        }
    }
}
