import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

@Suite("The configuration editor is a modal picker: arrows move and cycle, Enter commits, Escape cancels")
struct ConfigEditorControllerTests {
    private let rows = [
        ConfigSettingRow(
            path: ["ui", "tint"], title: "ui.tint", value: "off", choices: ["unset", "on", "off"], editable: true),
        ConfigSettingRow(
            path: ["ui", "spinner"], title: "ui.spinner", value: "line", choices: ["unset", "line", "dot"],
            editable: true),
        ConfigSettingRow(path: ["model"], title: "model", value: "unset", choices: [], editable: false)
    ]
    private func open() -> ScreenController {
        var controller = ScreenController(label: "m")
        controller.handle(
            .configEditor(ConfigEditorSnapshot(scope: "user", file: "/tmp/config.json", rows: rows, warnings: [])))
        return controller
    }
    private func key(_ controller: inout ScreenController, _ code: UInt32, modifiers: KeyModifiers = [])
        -> [ScreenController.Effect]
    {
        controller.handle(.key(KeyEvent(keyCode: code, modifiers: modifiers)), pageRows: 30)
    }

    @Test func `up down and arrows reach the editor only as navigation and never as draft text`() {
        var controller = open()
        #expect(key(&controller, Key.down.rawValue).isEmpty)
        #expect(key(&controller, Key.up.rawValue).isEmpty)
        #expect(key(&controller, Key.right.rawValue).isEmpty)
        #expect(key(&controller, Key.right.rawValue).isEmpty)
        #expect(key(&controller, Key.left.rawValue).isEmpty)
        #expect(controller.state.editor.text.isEmpty)
        #expect(controller.state.picker?.selected == 0)
        #expect(
            controller.state.picker?.matches[0].detail == "on", "off then on and back wraps within the real choices")
        _ = key(&controller, Key.down.rawValue)
        _ = key(&controller, Key.left.rawValue)
        #expect(controller.state.picker?.matches[1].detail == "unset", "left from line wraps to unset")
    }

    @Test func `enter commits the selected staged value and keeps the editor open`() {
        var controller = open()
        _ = key(&controller, Key.right.rawValue)
        #expect(
            key(&controller, Key.enter.rawValue) == [.commitConfig(scope: "user", path: ["ui", "tint"], value: "on")])
        #expect(controller.state.picker != nil)
    }

    @Test func `read-only rows do not cycle or commit`() {
        var controller = open()
        _ = key(&controller, Key.down.rawValue)
        _ = key(&controller, Key.down.rawValue)
        #expect(key(&controller, Key.right.rawValue).isEmpty)
        #expect(key(&controller, Key.enter.rawValue).isEmpty)
        #expect(controller.state.picker?.matches[2].detail == "unset")
    }

    @Test func `escape closes the editor and an update replaces rows without moving the selection`() {
        var controller = open()
        _ = key(&controller, Key.down.rawValue)
        #expect(key(&controller, 0x1B).isEmpty)
        #expect(controller.state.picker == nil)
        controller.handle(
            .configEditor(ConfigEditorSnapshot(scope: "user", file: "/tmp/config.json", rows: rows, warnings: [])))
        _ = key(&controller, Key.down.rawValue)
        let changed = [
            rows[0], rows[1],
            ConfigSettingRow(path: ["model"], title: "model", value: "claude", choices: [], editable: false)
        ]
        controller.handle(
            .configEditor(
                ConfigEditorSnapshot(
                    scope: "project", file: "/tmp/project.json", rows: changed, warnings: ["untrusted"])))
        #expect(controller.state.picker?.selected == 1)
        #expect(controller.state.picker?.kind == .config(scope: "project", file: "/tmp/project.json"))
        #expect(controller.state.picker?.matches[2].detail == "claude")
    }

    @Test func `the refresh after a key never closes a configuration editor`() {
        var controller = open()
        _ = key(&controller, UInt32(UnicodeScalar("x").value))
        #expect(controller.state.picker != nil)
        #expect(controller.state.editor.text.isEmpty)
    }
}
