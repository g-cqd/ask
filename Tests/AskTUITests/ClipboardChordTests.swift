internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// Command+C, X and V and their Ctrl twins copy, cut and paste, and never type a letter (roadmap 0082). A terminal with the kitty
/// keyboard protocol sends Command+C as `CSI 99;9u`: the letter with the super modifier.
@Suite("Command and Ctrl copy, cut and paste print nothing in the input")
struct ClipboardChordTests {
    private static let command = KeyModifiers.super

    private func rig(_ draft: String) -> PointerRig {
        var rig = PointerRig(
            columns: 100, options: ScreenOptions(prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: ["one", "two"])
        _ = rig.controller.handle(.paste(draft), pageRows: 10)
        rig.draw()
        return rig
    }

    private func key(_ letter: Character, _ modifiers: KeyModifiers = command) -> KeyEvent {
        KeyEvent(keyCode: UInt32(letter.asciiValue!), modifiers: modifiers)
    }

    @Test func `the kitty bytes for Command+C decode to c with the super modifier`() {
        var router = SequenceRouter()
        let events = router.feedAll(Array("\u{1B}[99;9u".utf8))
        guard case .key(let decoded) = events.first else {
            Issue.record("no key in \(events)")
            return
        }
        #expect(decoded.keyCode == 0x63 && decoded.modifiers == .super)
    }

    @Test(arguments: ["c", "x", "v", "a", "z", "C"] as [Character])
    func `no Command chord types its letter`(letter: Character) {
        var rig = rig("draft")
        _ = rig.controller.handle(.key(key(letter)), pageRows: 10)
        #expect(rig.controller.state.editor.text == "draft")
    }

    @Test func `Command+C copies a selection in the input and leaves the draft`() {
        var rig = rig("hello world")
        _ = rig.drag(from: (10, 6), to: (10, 9))
        #expect(rig.controller.handle(.key(key("c")), pageRows: 10) == [.copy("ello")])
        #expect(rig.controller.state.editor.text == "hello world")
    }

    @Test func `Command+X cuts a selection in the input`() {
        var rig = rig("hello world")
        _ = rig.drag(from: (10, 6), to: (10, 9))
        #expect(rig.controller.handle(.key(key("x")), pageRows: 10) == [.copy("ello")])
        #expect(rig.controller.state.editor.text == "h world")
    }

    @Test func `Command+C and Command+X with nothing selected do nothing`() {
        var rig = rig("draft")
        #expect(rig.controller.handle(.key(key("c")), pageRows: 10) == [])
        #expect(rig.controller.handle(.key(key("x")), pageRows: 10) == [])
        #expect(rig.controller.state.editor.text == "draft")
    }

    @Test(arguments: [
        KeyEvent(keyCode: 0x76, modifiers: .super), KeyEvent(keyCode: 0x76, modifiers: .ctrl), KeyEvent(keyCode: 0x16)
    ])
    func `Command+V and Ctrl+V paste the host pasteboard`(chord: KeyEvent) {
        var rig = rig("draft")
        #expect(rig.controller.handle(.key(chord), pageRows: 10) == [.pasteFromClipboard])
        #expect(rig.controller.state.editor.text == "draft")
    }

    @Test func `Ctrl+X with nothing selected still clears the draft`() {
        var rig = rig("draft")
        _ = rig.controller.handle(.key(key("x", .ctrl)), pageRows: 10)
        #expect(rig.controller.state.editor.text.isEmpty)
    }
}
