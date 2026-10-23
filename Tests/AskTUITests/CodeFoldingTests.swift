internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A long code block in a reply folds to one line, a click on that line or Ctrl+G opens it, and the rest of the reply stays as it was
/// (ADR-0046: `ui.codeFoldLines`; roadmap 0051).
@Suite("A long code block folds to a line and opens on a click")
struct CodeFoldingTests {
    private static let reply = "intro\n```swift\na\nb\nc\nd\n```\nafter"
    private static let ctrlG = KeyEvent(keyCode: UInt32(Character("g").asciiValue!), modifiers: .ctrl)
    private static let three = ScreenOptions(codeFoldLines: 3)

    private func rig(_ options: ScreenOptions = Self.three, _ text: String = Self.reply) -> PointerRig {
        PointerRig(options: options, updates: [.assistantText(text)])
    }

    private func rows(_ rig: PointerRig, _ range: ClosedRange<Int>) -> [String] { range.map { rig.text(row: $0) } }

    @Test func `a long block starts as a dim line between the text around it`() {
        let rig = rig()
        #expect(rows(rig, 7 ... 9) == ["intro", "code · swift · 4 lines", "after"])
        #expect(rig.buffer[8, 0].style.dim && !rig.buffer[7, 0].style.dim)
        #expect(rig.text(row: 6) == "")
    }

    @Test func `a click on the line opens it, and a click on the opening fence closes it`() {
        var rig = rig()
        rig.click(row: 8, col: 2)
        #expect(rows(rig, 2 ... 9) == ["intro", "```swift", "a", "b", "c", "d", "```", "after"])
        rig.click(row: 3, col: 1)
        #expect(rows(rig, 7 ... 9) == ["intro", "code · swift · 4 lines", "after"])
    }

    @Test func `a click in the code or the text around it does not toggle`() {
        var rig = rig()
        rig.click(row: 7, col: 1)
        rig.click(row: 9, col: 1)
        #expect(rig.text(row: 8) == "code · swift · 4 lines")
        rig.click(row: 8, col: 2)
        rig.click(row: 5, col: 0)
        rig.click(row: 8, col: 0)
        #expect(rig.text(row: 3) == "```swift")
    }

    @Test func `a block no longer than the limit is never folded`() {
        var rig = rig(ScreenOptions(codeFoldLines: 4))
        #expect(rig.text(row: 3) == "```swift")
        rig.click(row: 3, col: 1)
        #expect(rig.text(row: 3) == "```swift")
    }

    @Test func `control G opens every long block, and folds them again`() {
        var rig = rig(Self.three, Self.reply + "\n" + Self.reply)
        _ = rig.controller.handle(.key(Self.ctrlG), pageRows: 10)
        rig.draw()
        #expect(!rig.controller.state.transcript.codeFoldedByDefault)
        #expect(rig.text(row: 9) == "after" && rig.text(row: 8) == "```")
        _ = rig.controller.handle(.key(KeyEvent(keyCode: 0x07)), pageRows: 10)
        rig.draw()
        #expect(
            rows(rig, 4 ... 9) == [
                "intro", "code · swift · 4 lines", "after", "intro", "code · swift · 4 lines", "after"
            ])
        #expect(rig.controller.state.editor.text.isEmpty)
    }

    @Test func `with code open by default nothing is folded`() {
        let rig = rig(ScreenOptions(foldCode: false, codeFoldLines: 3))
        #expect(rig.text(row: 3) == "```swift")
    }

    @Test func `the screen's height caps the length a block may have before it folds`() {
        var rig = rig(ScreenOptions())
        #expect(rig.text(row: 3) == "```swift", "20 lines by default")
        rig.controller.setScreenRows(8)
        rig.draw()
        #expect(rig.text(row: 3) == "```swift", "half of eight rows is four, and four lines are not more than four")
        rig.controller.setScreenRows(7)
        rig.draw()
        #expect(rig.text(row: 8) == "code · swift · 4 lines")
    }

    @Test func `a selection reads what is shown: the line folded, the code open`() {
        var rig = rig()
        #expect(rig.drag(from: (7, 0), to: (9, 4)) == [.copy("intro\ncode · swift · 4 lines\nafter")])
        rig.click(row: 8, col: 2, after: .seconds(2))
        rig.click(row: 3, col: 1, after: .seconds(2))
        rig.click(row: 8, col: 2, after: .seconds(2))
        #expect(rig.drag(from: (4, 0), to: (7, 0)) == [.copy("a\nb\nc\nd")])
    }

    @Test func `opening a block while scrolled back keeps its line where it was`() {
        var rig = PointerRig(
            options: Self.three, lines: (1 ... 12).map { "line \($0)" }, updates: [.assistantText(Self.reply)])
        rig.controller.handle(.notice("tail 1", isError: false))
        rig.controller.handle(.notice("tail 2", isError: false))
        rig.draw()
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        guard let row = (0 ..< 10).first(where: { rig.text(row: $0) == "code · swift · 4 lines" }) else {
            Issue.record("the placeholder is not on screen")
            return
        }
        #expect(rig.controller.state.scrollback > 0)
        rig.click(row: row, col: 2)
        #expect(rig.text(row: row) == "```swift")
    }

    @Test func `a block streaming in folds once it is long, and a block opened earlier stays open`() {
        var rig = rig()
        rig.click(row: 8, col: 2)
        rig.controller.handle(.assistantText("\n```\n1\n2"))
        rig.draw()
        #expect(rig.text(row: 9) == "2", "two lines are not long")
        rig.controller.handle(.assistantText("\n3\n4"))
        rig.draw()
        #expect(rig.text(row: 9) == "code · 4 lines")
        #expect((0 ..< 10).contains { rig.text(row: $0) == "```swift" }, "the first block keeps the choice made for it")
    }
}
