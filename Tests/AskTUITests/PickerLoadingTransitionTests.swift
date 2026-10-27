import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

@Suite("Picker loading transitions never produce a negative match index")
struct PickerLoadingTransitionTests {
    private let trigger = CompletionTrigger(range: 7 ..< 7, query: "")
    private let rows = (0 ..< 9)
        .map { PickerRow(ChoiceRow(label: "model\($0)", arguments: "m\($0)"), command: "model") }

    @Test(arguments: [0, 1, 3])
    func `repeated empty refreshes followed by results keep the first choice valid`(_ refreshes: Int) throws {
        var picker = CompletionPicker(kind: .choices(title: "model"), trigger: trigger, matches: [], capacity: 7)
        for _ in 0 ..< refreshes {
            var next = CompletionPicker(kind: picker.kind, trigger: trigger, matches: [], capacity: 7)
            next.keepChoice(from: picker)
            #expect(next.selected == 0 && next.firstVisible == 0)
            picker = next
        }
        var loaded = CompletionPicker(kind: picker.kind, trigger: trigger, matches: rows, capacity: 7)
        loaded.keepChoice(from: picker)
        try #require(loaded.selected == 0)
        #expect(ScreenComposer.window(of: loaded, rows: 8) == 0 ..< 7)
        #expect(ScreenComposer.pickerLines(loaded, columns: 60, rows: 8).count == 8)
    }

    @Test func `refreshing a scrolled choice through an empty list resets its window`() throws {
        var old = CompletionPicker(kind: .choices(title: "model"), trigger: trigger, matches: rows, capacity: 3)
        old.move(8)
        var loading = CompletionPicker(kind: old.kind, trigger: trigger, matches: [], capacity: 3)
        loading.keepChoice(from: old)
        try #require(loading.selected == 0 && loading.firstVisible == 0)
        #expect(loading.visible.isEmpty)
        var shrunk = CompletionPicker(kind: old.kind, trigger: trigger, matches: Array(rows.prefix(2)), capacity: 3)
        shrunk.keepChoice(from: old)
        #expect(shrunk.selected == 1 && shrunk.firstVisible == 0)
    }

    @Test func `model Enter can render loading refreshes results and then choose`() throws {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "model", summary: "Choose", takesChoices: true)])
        _ = screen.handle(.paste("/model"), pageRows: 30)
        #expect(
            screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30) == [.listChoices(command: "model")]
        )
        _ = screen.refreshPicker(screenRows: 30, at: .now)
        var composer = ScreenComposer()
        var buffer = ScreenBuffer(columns: 122, rows: 31)
        _ = composer.compose(screen.state, into: &buffer)
        screen.handle(.choices(command: "model", rows: [ChoiceRow(label: "Example", arguments: "provider model")]))
        let picker = try #require(screen.state.picker)
        try #require(picker.selected == 0)
        _ = composer.compose(screen.state, into: &buffer)
        #expect(
            screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30) == [
                .runCommand(name: "model", arguments: "provider model")
            ])
    }
}
