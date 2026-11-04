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
        // In a thread's lane a message is the thread's (roadmap 0194); a command still goes back to main.
        if case .prompt(let text) = SlashInput(line), let effects = sendToThread(text) {
            history.record(line)
            return effects
        }
        // `/reload` keeps the lane: the new build shows it again (roadmap 0195).
        if case .command("reload", let arguments) = SlashInput(line), state.lane?.isThread == true {
            history.record(line)
            return [.runCommand(name: "reload", arguments: arguments)]
        }
        // `/thread` in a thread's lane starts one from that thread, under it in the tree; the lane stays.
        if case .command("thread", let arguments) = SlashInput(line), let lane = state.lane, lane.isThread {
            history.record(line)
            return [.startThread(from: lane.id, text: arguments)]
        }
        leaveLane()
        history.record(line)
        switch SlashInput(line) {
            case .prompt(let text):
                return submitPrompt(Self.isContinueWord(text) ? Self.continueText : text, followUp: followUp)
            case .command(let name, let arguments):
                guard let command = SlashCommand.named(name, in: commands) else {
                    state.transcript.addUser(line)
                    state.transcript.addNotice("There is no command /\(name); /help lists them.", isError: true)
                    return []
                }
                // The conversation's commands decide below how their line is shown (roadmap 0113); the screen's own show it now.
                if SlashCommand.named(name, in: Self.builtIn) != nil { state.transcript.addUser(line) }
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
                            state.transcript.addUser(line)
                            state.editor.paste("/\(command.name) ")
                            pickerScreenRows = Swift.max(pickerScreenRows, Self.pickerMinimumRows)
                            return refreshPicker(screenRows: pickerScreenRows, at: .now)
                        }
                        return runCommand(command, arguments: arguments, line: line)
                }
        }
    }
}
