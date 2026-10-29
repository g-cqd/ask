internal import TerminalKitCodecs
internal import TerminalKitInput

/// The list a command offers after its name (ADR-0117): `/model `, `/thinking `, `/login `, `/logout `. The same picker as the commands' and
/// the files', with the same keys and the same click; the difference is that a choice runs the command at once, with the row's arguments.
extension ScreenController {
    /// How old a list may be before the next time it opens asks for a fresh one.
    static let choicesMaxAge = Duration.seconds(30)

    /// The command whose choices the draft is asking for, and the text after its name, when the draft is `/command ` and what follows.
    func choiceTrigger() -> (command: SlashCommand, trigger: CompletionTrigger)? {
        let text = state.editor.text
        guard text.first == "/", !text.contains("\n"), let space = text.firstIndex(where: \.isWhitespace) else {
            return nil
        }
        let name = String(text[text.index(after: text.startIndex) ..< space])
        guard let command = commands.first(where: { $0.name == name && $0.takesChoices }) else { return nil }
        let argumentsStart = text.index(after: space)
        let offset = text.distance(from: text.startIndex, to: argumentsStart)
        guard state.editor.cursor >= offset else { return nil }
        let query = String(text[argumentsStart...].drop(while: \.isWhitespace))
        return (command, CompletionTrigger(range: offset ..< text.count, query: query))
    }

    /// Opens, narrows or closes the picker over a command's choices.
    /// - Returns: asking for the list, when there is none or it has aged.
    mutating func refreshChoicePicker(
        // @dl:accept -- the file picker and this one both honour the word the user closed the list on and ask for a missing list once
        _ command: SlashCommand, _ trigger: CompletionTrigger, screenRows: Int, at now: ContinuousClock.Instant
    ) -> [Effect] {
        guard state.pickerDismissedAt != trigger.range.lowerBound else {
            state.picker = nil
            return []
        }
        var effects: [Effect] = []
        let held = state.choices[command.name]
        if held.map({ $0.stale || now - $0.at > Self.choicesMaxAge }) ?? true, !asking.contains(command.name) {
            asking.insert(command.name)
            effects = [.listChoices(command: command.name)]
        }
        let capacity = CompletionPicker.capacity(screenRows: screenRows)
        guard let held else {
            install(
                CompletionPicker(
                    kind: .choices(title: command.name), trigger: trigger, matches: [], capacity: capacity,
                    caption: "looking…"))
            return effects
        }
        let ranked = PickerRanking.rank(held.rows, query: trigger.query)
        guard !ranked.isEmpty else {
            state.picker = nil
            return effects
        }
        install(
            CompletionPicker(
                kind: .choices(title: command.name), trigger: trigger,
                matches: ranked.map { PickerRow($0, command: command.name) }, capacity: capacity,
                caption: held.rows.count > ranked.count ? "\(ranked.count) of \(held.rows.count)" : ""))
        return effects
    }

    /// Takes the list a command offered, and refreshes the picker the person may be waiting on.
    mutating func receive(command: String, choices rows: [ChoiceRow]) -> [Effect] {
        asking.remove(command)
        state.choices[command] = ChoiceList(rows: rows, at: .now)
        guard pickerScreenRows >= Self.pickerMinimumRows, let found = choiceTrigger(), found.command.name == command
        else { return [] }
        return refreshChoicePicker(found.command, found.trigger, screenRows: pickerScreenRows, at: .now)
    }

    /// A finished prompt or command can change any list (`/tree` gains a prompt, `/resume` a session, `/logout` an account): each is asked
    /// for again the next time it opens, and shown as it was until the answer comes.
    mutating func markChoicesStale() {
        for name in state.choices.keys { state.choices[name]?.stale = true }
        asking.removeAll()
    }

    /// Runs the command a chosen row stands for: the draft is cleared, the line is shown as if it had been typed, and the command starts.
    mutating func run(_ row: PickerRow, command: String, arguments: String) -> [Effect] {
        state.picker = nil
        state.editor.clear()
        guard !busy() else { return [] }
        state.transcript.addUser("/\(command) \(arguments)")
        return begin(.runCommand(name: command, arguments: arguments))
    }
}
