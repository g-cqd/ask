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
        guard screenRows >= Self.pickerMinimumRows else { return closePicker() }
        if let trigger = commandTrigger() {
            refreshCommandPicker(trigger, screenRows: screenRows)
            // The skills are listed the first time a command picker could open, which is the first `/`, and never at launch.
            guard !state.skillsRequested else { return [] }
            state.skillsRequested = true
            return [.listSkills]
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
            !offered.contains(where: { $0.name == trigger.query })
        else {
            state.picker = nil
            return
        }
        install(
            CompletionPicker(
                kind: .commands, trigger: trigger, matches: matches.map(PickerRow.init),
                capacity: CompletionPicker.capacity(screenRows: screenRows)))
    }

    /// Shows `picker`, keeping the choice when it is the same word with the same query.
    mutating func install(_ picker: CompletionPicker) {
        var picker = picker
        if let old = state.picker { picker.keepChoice(from: old) }
        state.picker = picker
    }

    /// A click on the picker's match `index`, as the last frame drew it: the same as choosing it and pressing Enter. Nothing happens when
    /// the list has moved on since that frame, because the click meant a row that is no longer there, or while a question has the keys.
    mutating func clickPicker(match index: Int) {
        guard var picker = state.picker, state.pendingApproval == nil, picker.trigger == frame.pickerTrigger,
            picker.matches.indices.contains(index)
        else { return }
        picker.choose(index)
        _ = accept(picker)
    }

    /// What an open picker does with `key`, or nil when the key is the editor's.
    mutating func pickerKey(_ key: KeyEvent, screenRows: Int) -> [Effect]? {
        guard screenRows >= Self.pickerMinimumRows, var picker = state.picker else { return nil }
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

    /// Puts the chosen command in the draft where the word was. Nothing is sent: a second Enter runs it.
    mutating func accept(_ picker: CompletionPicker) -> [Effect] {
        if picker.matches.indices.contains(picker.selected) {
            state.editor.replace(picker.trigger.range, with: picker.matches[picker.selected].insertion)
        }
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
