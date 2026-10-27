internal import TerminalKitCodecs
internal import TerminalKitInput

/// A submitted line: a prompt, a command, or a command that does not exist.
extension ScreenController {
    mutating func submit(_ line: String, followUp: Bool) -> [Effect] {
        leaveLane()
        switch SlashInput(line) {
            case .prompt(let text):
                return submitPrompt(text, followUp: followUp)
            case .command(let name, let arguments):
                state.transcript.addUser(line)
                guard let command = commands.first(where: { $0.name == name }) else {
                    state.transcript.addNotice("There is no command /\(name); /help lists them.", isError: true)
                    return []
                }
                switch command.name {
                    case "help":
                        let help = commands.map { "/\($0.name)  \($0.summary)" }.joined(separator: "\n")
                        state.transcript.addNotice(help, isError: false)
                        return []
                    case "quit": return [.quit]
                    case "tasks": return toggleRunners(announcing: true)
                    case "sidebar": return toggleSidebar(announcing: true)
                    case "verbose": return toggleVerbose()
                    case "follow-up": return submitPrompt(arguments, followUp: true)
                    default:
                        guard !busy() else { return [] }
                        return begin(.runCommand(name: name, arguments: arguments))
                }
        }
    }
}
