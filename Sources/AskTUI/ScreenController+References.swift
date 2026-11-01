/// The picker at a `#` that starts a word (roadmap 0186): the session's tasks and ideas, which the conversation lists as the choices of
/// `#`, asked for once and again once stale, as a command's list is. What is chosen replaces the word.
extension ScreenController {
    static let referenceList = "#"

    func referenceTrigger() -> CompletionTrigger? { trigger("#") { $0.isLetter || $0.isNumber } }

    mutating func refreshReferencePicker(_ trigger: CompletionTrigger, screenRows: Int) -> [Effect] {
        var effects: [Effect] = []
        let held = state.choices[Self.referenceList]
        if held.map({ $0.stale || .now - $0.at > Self.choicesMaxAge }) ?? true, !asking.contains(Self.referenceList) {
            asking.insert(Self.referenceList)
            effects = [.listChoices(command: Self.referenceList)]
        }
        let rows = PickerRanking.rank(held?.rows ?? [], query: "#" + trigger.query)
        guard state.pickerDismissedAt != trigger.range.lowerBound, !rows.isEmpty,
            !(rows.count == 1 && rows[0].label == "#" + trigger.query)
        else {
            state.picker = nil
            return effects
        }
        install(
            CompletionPicker(
                kind: .references,
                trigger: trigger,
                matches: rows.map { PickerRow(label: $0.label, detail: $0.detail, insertion: $0.label) },
                capacity: CompletionPicker.capacity(screenRows: screenRows)
            )
        )
        return effects
    }

    /// The tokens the screen draws: the skills' and the references' names, with their sigils.
    mutating func refreshTokens() {
        let skills = (state.skills ?? []).map { "/" + $0.name }
        let references = state.choices[Self.referenceList]?.rows.map(\.label) ?? []
        state.transcript.setTokenNames(Set(skills + references))
    }
}
