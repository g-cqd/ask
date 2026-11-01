/// The picker at a `/` that starts a later word of the draft (roadmap 0185): the skills alone, since a command is one only as the first
/// word; what is chosen replaces the word, as the first word's picker does.
extension ScreenController {
    /// The `/` word the cursor is in, shaped as a skill's name could be. Asked only after the first word's command picker, which takes a
    /// `/` that starts the draft.
    func inlineSkillTrigger() -> CompletionTrigger? {
        let text = state.editor.text
        guard Self.contains(UInt8(ascii: "/"), in: text),
            let trigger = CompletionTrigger.at(cursor: state.editor.cursor, in: text, sigils: ["/"]),
            trigger.query.allSatisfy({
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ":" || $0 == "_")
            })
        else { return nil }
        return trigger
    }

    /// Opens, narrows or closes the skills' picker for `trigger`; closed for no match, a name typed in full, or a word closed on.
    mutating func refreshInlineSkillPicker(_ trigger: CompletionTrigger, screenRows: Int) -> [Effect] {
        let skills = state.skills ?? []
        let matches = PickerRanking.rank(skills, query: trigger.query)
        if state.pickerDismissedAt == trigger.range.lowerBound || matches.isEmpty
            || SlashCommand.named(trigger.query, in: skills) != nil
        {
            state.picker = nil
        } else {
            install(
                CompletionPicker(
                    kind: .commands,
                    trigger: trigger,
                    matches: Self.groupedByCategory(matches),
                    capacity: CompletionPicker.capacity(screenRows: screenRows)
                )
            )
        }
        guard state.skills == nil, !state.skillsRequested else { return [] }
        state.skillsRequested = true
        return [.listSkills]
    }
}
