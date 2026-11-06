internal import TerminalKitCodecs
internal import TerminalKitInput

/// A submitted line: a prompt, a command, or a command that does not exist.
extension ScreenController {
    /// A prompt of the session being shown again (a resume): in the conversation, and in the history Up browses (roadmap 0111).
    mutating func replayPrompt(_ text: String) {
        state.transcript.addUser(text)
        history.record(text)
    }

    /// The commands that are a thread's lane's own (roadmap 0195), keeping the lane: `/thread` starts one from that thread, under it;
    /// `/rename TITLE` names it; `/merge` (or `/close`) merges it now; `/reload` comes back to it. Nil for anything else, or outside a thread's lane.
    private func threadLaneCommand(_ line: String) -> [Effect]? {
        guard let lane = state.lane, lane.isThread, case .command(let name, let arguments) = SlashInput(line) else {
            return nil
        }
        switch name {
            case "thread": return [.startThread(from: lane.id, text: arguments)]
            case "rename": return [.renameThread(id: lane.id, title: arguments)]
            case "merge", "close": return [.mergeThread(id: lane.id)]
            case "reload": return [.runCommand(name: "reload", arguments: arguments)]
            default: return nil
        }
    }

    mutating func submit(_ line: String, followUp: Bool) -> [Effect] {
        // In a thread's lane a message is the thread's (roadmap 0194); a command still goes back to main.
        if case .prompt(let text) = SlashInput(line), let effects = sendToThread(text) {
            history.record(line)
            return effects
        }
        if let effects = threadLaneCommand(line) {
            history.record(line)
            return effects
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
                // The conversation's commands decide below how their line is shown (roadmap 0113); the screen's own show it now,
                // except `/sidebar`, whose answer is the sidebar itself (note n28).
                if SlashCommand.named(name, in: Self.builtIn) != nil, !(name == "sidebar" && arguments.isEmpty) {
                    state.transcript.addUser(line)
                }
                switch command.name {
                    case "help":
                        let help = commands.map { "/\($0.name)  \($0.summary)" }.joined(separator: "\n")
                        state.transcript.addNotice(help, isError: false)
                        return []
                    case "quit": return [.quit]
                    case "jobs": return toggleRunners(announcing: true)
                    case "sidebar" where arguments == "jobs":
                        // Where a thread's jobs are listed, for this run (roadmap 0195; `ui.sidebarJobs` sets where it starts).
                        state.jobsInTree.toggle()
                        let where_ = state.jobsInTree ? "under the thread that started them" : "in the Jobs section"
                        state.transcript.addNotice("Jobs are listed \(where_).", isError: false)
                        return []
                    case "sidebar": return toggleSidebar(announcing: true)
                    case "verbose": return toggleVerbose()
                    case "follow-up": return submitPrompt(arguments, followUp: true)
                    case "continue": return submitPrompt(Self.continueText(with: arguments), followUp: followUp)
                    default:
                        // A list known to be empty has nothing to open: the bare command runs and says why.
                        let knownEmpty = state.choices[command.name].map { $0.rows.isEmpty && !$0.stale } ?? false
                        if command.takesChoices, arguments.isEmpty, !knownEmpty {
                            if !command.summarises { state.transcript.addUser(line) }
                            state.editor.paste("/\(command.name) ")
                            pickerScreenRows = Swift.max(pickerScreenRows, Self.pickerMinimumRows)
                            return refreshPicker(screenRows: pickerScreenRows, at: .now)
                        }
                        return runCommand(command, arguments: arguments, line: line)
                }
        }
    }
}
