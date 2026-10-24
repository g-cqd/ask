internal import TerminalKitCodecs
internal import TerminalKitInput

/// The command picker's behaviour (roadmap 0048, ADR-0067): derived from the draft after every key, and taking Up, Down, Tab, Enter
/// and Escape while it is open. Enter and Tab insert the choice and never send it.
extension ScreenController {
    /// The least screen height that offers a picker. Below it the keys keep their ordinary meaning, because a list nobody can see
    /// must not take Enter.
    static let pickerMinimumRows = 12

    /// Brings the picker in line with the draft.
    ///
    /// It is open for a command-shaped word that starts the draft, when something matches, unless the name is already typed in full
    /// (nothing is left to insert, so Enter runs it as it always did) or the user closed it on this word.
    mutating func refreshPicker(screenRows: Int) {
        let text = state.editor.text
        // A command word can only start a draft that starts with a slash: checking that first keeps an ordinary keystroke, in a
        // draft of any length, from walking the draft to look for a trigger (measured: 6 KB draft, 65 to about 36 microseconds).
        guard screenRows >= Self.pickerMinimumRows, text.first(where: { !$0.isWhitespace }) == "/",
            let trigger = CompletionTrigger.at(cursor: state.editor.cursor, in: text, sigils: ["/"]),
            text.prefix(trigger.range.lowerBound).allSatisfy(\.isWhitespace),
            trigger.query.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else {
            state.picker = nil
            state.pickerDismissedAt = nil
            return
        }
        let matches = PickerRanking.rank(commands, query: trigger.query)
        guard state.pickerDismissedAt != trigger.range.lowerBound, !matches.isEmpty,
            !commands.contains(where: { $0.name == trigger.query })
        else {
            state.picker = nil
            return
        }
        var picker = CompletionPicker(
            kind: .commands, trigger: trigger, matches: matches.map(PickerRow.init),
            capacity: CompletionPicker.capacity(screenRows: screenRows))
        if let old = state.picker { picker.keepChoice(from: old) }
        state.picker = picker
    }

    /// What an open picker does with `key`, or nil when the key is the editor's.
    mutating func pickerKey(_ key: KeyEvent, screenRows: Int) -> [Effect]? {
        guard screenRows >= Self.pickerMinimumRows, var picker = state.picker else { return nil }
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
    private mutating func accept(_ picker: CompletionPicker) -> [Effect] {
        if picker.matches.indices.contains(picker.selected) {
            state.editor.replace(picker.trigger.range, with: picker.matches[picker.selected].insertion)
        }
        state.picker = nil
        return []
    }
}
