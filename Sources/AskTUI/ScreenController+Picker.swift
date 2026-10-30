internal import TerminalKitCodecs
internal import TerminalKitInput

/// The command picker's behaviour (roadmap 0048, ADR-0067): derived from the draft after every key, and taking Up, Down, Tab, Enter
/// and Escape while it is open. Enter and Tab insert the choice and never send it.
extension ScreenController {
    /// The least screen height that offers a picker. Below it the keys keep their ordinary meaning, because a list nobody can see
    /// must not take Enter.
    static let pickerMinimumRows = 12

    /// Brings the picker in line with the draft: the command picker for a command word that starts it, the file picker for an `@` word
    /// anywhere, none otherwise.
    /// - Returns: asking for the project's files, when an `@` word needs a listing that is missing or old.
    mutating func refreshPicker(screenRows: Int, at now: ContinuousClock.Instant) -> [Effect] {
        // The configuration editor is modal: keys belong to it, not to the draft or a word picker.
        if case .config = state.picker?.kind { return [] }
        // A recalled command is not being typed: its picker would take the next Up from the history (roadmap 0111).
        guard screenRows >= Self.pickerMinimumRows, !history.isShowing(state.editor.text) else { return closePicker() }
        if let trigger = commandTrigger() {
            refreshCommandPicker(trigger, screenRows: screenRows)
            // The skills are listed the first time a command picker could open, which is the first `/`, and never at launch.
            guard !state.skillsRequested else { return [] }
            state.skillsRequested = true
            return [.listSkills]
        }
        if let found = choiceTrigger() {
            return refreshChoicePicker(found.command, found.trigger, screenRows: screenRows, at: now)
        }
        if let trigger = fileTrigger() { return refreshFilePicker(trigger, screenRows: screenRows, at: now) }
        return closePicker()
    }

    /// Closes the picker and forgets that the user ever closed one: the cursor is in no word it could belong to.
    private mutating func closePicker() -> [Effect] {
        state.picker = nil
        state.pickerDismissedAt = nil
        return []
    }

    /// The command word the cursor is in, if there is one: command-shaped, and the first word of the draft.
    func commandTrigger() -> CompletionTrigger? {
        let text = state.editor.text
        // A command word can only start a draft that starts with a slash: checking that first keeps an ordinary keystroke, in a
        // draft of any length, from walking the draft to look for a trigger (measured: 6 KB draft, 65 to about 36 microseconds).
        guard text.first(where: { !$0.isWhitespace }) == "/",
            let trigger = CompletionTrigger.at(cursor: state.editor.cursor, in: text, sigils: ["/"]),
            text.prefix(trigger.range.lowerBound).allSatisfy(\.isWhitespace),
            trigger.query.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ":") })
        else { return nil }
        return trigger
    }

    /// Opens, narrows or closes the command picker for `trigger`. It stays closed for a name typed in full (nothing is left to insert, so
    /// Enter runs it as it always did), for no match, and for a word the user closed it on.
    mutating func refreshCommandPicker(_ trigger: CompletionTrigger, screenRows: Int) {
        let offered = commands + (state.skills ?? [])
        let matches = PickerRanking.rank(offered, query: trigger.query)
        guard state.pickerDismissedAt != trigger.range.lowerBound, !matches.isEmpty,
            SlashCommand.named(trigger.query, in: offered) == nil
        else {
            state.picker = nil
            return
        }
        install(
            CompletionPicker(
                kind: .commands, trigger: trigger, matches: Self.groupedByCategory(matches),
                capacity: CompletionPicker.capacity(screenRows: screenRows)))
    }

    /// Commands under one dim heading per category, in the categories' fixed order.
    static func groupedByCategory(_ commands: [SlashCommand]) -> [PickerRow] {
        var rows: [PickerRow] = []
        for category in SlashCommand.Category.allCases {
            let inCategory = commands.filter { $0.category == category }
            guard !inCategory.isEmpty else { continue }
            rows.append(PickerRow(heading: category.heading))
            rows += inCategory.map(PickerRow.init)
        }
        return rows
    }

    /// Shows `picker`, keeping the choice when it is the same word with the same query.
    mutating func install(_ picker: CompletionPicker) {
        var picker = picker
        if let old = state.picker { picker.keepChoice(from: old) }
        picker.snapSelectionToChoice()
        state.picker = picker
    }

    /// A click on the picker's match `index`, as the last frame drew it: the same as choosing it and pressing Enter. Nothing happens when
    /// the list has moved on since that frame, because the click meant a row that is no longer there, or while a question has the keys.
    mutating func clickPicker(match index: Int) -> [Effect] {
        guard var picker = state.picker, state.pendingApproval == nil, state.pendingQuestions == nil,
            state.pendingInput == nil,
            picker.trigger == frame.pickerTrigger, picker.matches.indices.contains(index),
            !picker.matches[index].isHeading
        else { return [] }
        picker.choose(index)
        return accept(picker)
    }

    /// What an open picker does with `key`, or nil when the key is the editor's.
    mutating func pickerKey(_ key: KeyEvent, screenRows: Int) -> [Effect]? {
        guard screenRows >= Self.pickerMinimumRows, var picker = state.picker else { return nil }
        // The configuration editor owns every key while it is open: arrows move and cycle, Enter saves, Escape closes.
        if picker.kind.isConfig {
            switch key.keyCode {
                case Key.up.rawValue: picker.move(-1)
                case Key.down.rawValue: picker.move(1)
                case Key.left.rawValue: cycleConfig(&picker, by: -1)
                case Key.right.rawValue: cycleConfig(&picker, by: 1)
                case Key.enter.rawValue where !key.modifiers.contains(.shift): return accept(picker)
                case 0x1B:
                    state.pickerDismissedAt = picker.trigger.range.lowerBound
                    state.picker = nil
                    return []
                default: break
            }
            state.picker = picker
            return []
        }
        // A picker with nothing to choose yet (the files are still being listed) only answers Escape; every other key is the editor's.
        if picker.matches.isEmpty, key.keyCode != 0x1B { return nil }
        switch key.keyCode {
            case Key.up.rawValue: picker.move(-1)
            case Key.down.rawValue: picker.move(1)
            case Key.tab.rawValue: return accept(picker)
            case Key.enter.rawValue where !key.modifiers.contains(.shift): return accept(picker)
            case 0x1B:
                state.pickerDismissedAt = picker.trigger.range.lowerBound
                state.picker = nil
                return []
            default: return nil
        }
        state.picker = picker
        return []
    }

    /// Puts the chosen command in the draft where the word was. Nothing is sent: a second Enter runs it. A choice from a command's list is
    /// different: it runs that command at once, with the row's arguments.
    /// Left/right cycle the selected setting's staged value. A read-only row has no choices and does not move.
    private mutating func cycleConfig(_ picker: inout CompletionPicker, by step: Int) {
        guard picker.matches.indices.contains(picker.selected) else { return }
        let index = picker.selected
        let choices = picker.matches[index].choices
        let real = choices.filter { $0 != "unset" }
        guard !real.isEmpty else { return }
        let detail = picker.matches[index].detail
        let next: String
        if detail == "unset" {
            next = step > 0 ? real[0] : real[real.count - 1]
        } else if let current = real.firstIndex(of: detail) {
            if step > 0 {
                next = current == real.count - 1 ? real[0] : real[current + 1]
            } else {
                next = current == 0 ? "unset" : real[current - 1]
            }
        } else {
            return
        }
        picker.matches[index].detail = next
    }

    mutating func accept(_ picker: CompletionPicker) -> [Effect] {
        guard picker.matches.indices.contains(picker.selected) else {
            state.picker = nil
            return []
        }
        let row = picker.matches[picker.selected]
        guard !row.isHeading else { return [] }
        if case .config(let scope, _) = picker.kind {
            guard !row.choices.isEmpty else { return [] }
            return [.commitConfig(scope: scope, path: row.path, value: row.detail)]
        }
        if case .choices(let title) = picker.kind, let arguments = row.run {
            return run(row, command: title, arguments: arguments)
        }
        state.editor.replace(picker.trigger.range, with: row.insertion)
        // A row that asked to be finished leaves the list closed, or it would offer itself again at once.
        if case .choices = picker.kind { state.pickerDismissedAt = picker.trigger.range.lowerBound }
        state.picker = nil
        return []
    }
}

extension ScreenController {
    /// Takes the skills the conversation listed, and refreshes the command picker the user may be waiting on.
    mutating func receive(skills: [SlashCommand]) {
        state.skills = skills
        guard pickerScreenRows >= Self.pickerMinimumRows, let trigger = commandTrigger() else { return }
        refreshCommandPicker(trigger, screenRows: pickerScreenRows)
    }
}
