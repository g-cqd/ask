import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

@Suite("The command picker groups commands under non-selectable headings")
struct CommandCategoryPickerTests {
    private static let commands = [
        SlashCommand(name: "resume", summary: "Choose a session.", category: .session),
        SlashCommand(name: "model", summary: "Choose a model.", category: .model),
        SlashCommand(name: "mcp", summary: "Show the MCP servers.", category: .tools),
        SlashCommand(name: "config", summary: "Edit settings.", category: .configuration)
    ]

    private func controller(_ typing: String = "/", commands: [SlashCommand] = commands) -> ScreenController {
        var controller = ScreenController(label: "m", commands: commands, options: .legacy)
        for scalar in typing.unicodeScalars {
            _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        return controller
    }

    private func drawn(_ controller: ScreenController, columns: Int = 60, rows: Int = 30) -> [String] {
        var buffer = ScreenBuffer(columns: columns, rows: rows)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        return (0 ..< rows)
            .map { row in
                var text = ""
                for column in 0 ..< columns {
                    let cell = buffer[row, column]
                    if !cell.isContinuation { text.append(cell.character) }
                }
                while text.hasSuffix(" ") { text.removeLast() }
                return text
            }
    }

    @Test func `every category draws one dim heading above its first command`() throws {
        let controller = controller()
        let shown = drawn(controller)
        let headings = shown.filter { $0 == "session" || $0 == "model" || $0 == "tools" || $0 == "configuration" }
        #expect(headings.first == "session", "the first heading is the first category")
        let sessionRow = try #require(shown.firstIndex(of: "session"))
        #expect(shown[sessionRow + 1].hasPrefix("/help"), "the heading sits above its category's first command")
        let structure = try #require(controller.state.picker).matches
        #expect(
            structure.filter { $0.isHeading }.map { $0.detail }
                == ["session", "model", "tools", "configuration"], "stable category order")
        #expect(structure[1].label == "/help" && structure[2].label == "/quit")
    }

    @Test func `selection and movement never stop on a heading`() throws {
        let first = controller()
        let picker = try #require(first.state.picker)
        let selectable = picker.matches.filter { !$0.isHeading }
        #expect(selectable.count == 10, "every command, built-in and offered, remains selectable")
        #expect(picker.matches.first?.isHeading == true, "the first row is a heading")
        #expect(picker.selected == 1, "the selection starts on the first command, not the heading")
        #expect(picker.countOfChoices == 10)
        var down = controller()
        for _ in 0 ..< 20 { _ = down.handle(.key(KeyEvent(keyCode: Key.down.rawValue)), pageRows: 30) }
        let after = try #require(down.state.picker)
        #expect(!after.matches[after.selected].isHeading, "twenty downs never land on a heading")
        var up = controller()
        for _ in 0 ..< 20 { _ = up.handle(.key(KeyEvent(keyCode: Key.up.rawValue)), pageRows: 30) }
        let wrapped = try #require(up.state.picker)
        #expect(!wrapped.matches[wrapped.selected].isHeading, "twenty ups never land on a heading")
    }

    @Test func `a click on a heading does nothing and on a command still chooses`() throws {
        var rig = PointerRig(columns: 60, rows: 30)
        _ = rig.controller.handle(.paste("/"), pageRows: 30)
        rig.draw()
        let headingRow = try #require((0 ..< 30).first { rig.text(row: $0) == "session" })
        let selectedBefore = rig.controller.state.picker?.selected
        #expect(rig.mouse(.left, .press, row: headingRow, col: 1).isEmpty)
        #expect(rig.controller.state.picker?.selected == selectedBefore, "a heading press does not choose")
        rig.mouse(.left, .release, row: headingRow, col: 1)
        #expect(rig.controller.state.picker != nil)
        let commandRow = try #require((0 ..< 30).first { rig.text(row: $0).hasPrefix("/help") })
        rig.click(row: commandRow, col: 2)
        #expect(rig.controller.state.editor.text == "/help ", "a command click still inserts")
    }

    @Test func `searching and insertion still work with headings`() throws {
        var controller = controller("/mo")
        let picker = try #require(controller.state.picker)
        #expect(picker.matches.filter { !$0.isHeading }.map { $0.label } == ["/model"])
        #expect(
            picker.matches.filter { $0.isHeading }.map { $0.detail } == ["model"],
            "only the matching group's heading shows")
        _ = controller.handle(.key(KeyEvent(keyCode: Key.tab.rawValue)), pageRows: 30)
        #expect(controller.state.editor.text == "/model ")
    }

    @Test func `the position count includes commands but not headings`() throws {
        let controller = controller()
        let picker = try #require(controller.state.picker)
        #expect(picker.countOfChoices == 10)
        var buffer = ScreenBuffer(columns: 60, rows: 30)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        var title = ""
        for row in 0 ..< 30 {
            for column in 0 ..< 60 {
                let cell = buffer[row, column]
                if !cell.isContinuation { title.append(cell.character) }
            }
            if title.contains("commands") { break }
            title = ""
        }
        #expect(title.contains("1 of 10"), "the title counts commands, never headings")
    }

    @Test func `small screens keep working and headings take no extra rows when hidden`() throws {
        let controller = controller(
            "/", commands: [SlashCommand(name: "only", summary: "One.", category: .session)])
        var buffer = ScreenBuffer(columns: 50, rows: 12)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        #expect(composer.transcriptRows >= 1)
        #expect(
            (0 ..< 12)
                .contains { row in
                    var text = ""
                    for column in 0 ..< 50 {
                        let cell = buffer[row, column]
                        if !cell.isContinuation { text.append(cell.character) }
                    }
                    return text.hasPrefix("/only")
                })
    }
}
