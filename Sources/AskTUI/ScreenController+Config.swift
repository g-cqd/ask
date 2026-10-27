internal import TerminalKitCodecs
internal import TerminalKitInput

/// The interactive configuration editor (roadmap 0079): a modal list over `CompletionPicker`, where left/right
/// cycle a value and Enter asks the composition root to commit it.
extension ScreenController {
    mutating func receive(config snapshot: ConfigEditorSnapshot) -> [Effect] {
        let picker = CompletionPicker(
            kind: .config(scope: snapshot.scope, file: snapshot.file),
            trigger: CompletionTrigger(range: 0 ..< 0, query: ""),
            matches: snapshot.rows.map(PickerRow.init), capacity: 7)
        install(picker)
        if !snapshot.warnings.isEmpty {
            state.transcript.addNotice(snapshot.warnings.joined(separator: "\n"), isError: false)
        }
        return []
    }
}
