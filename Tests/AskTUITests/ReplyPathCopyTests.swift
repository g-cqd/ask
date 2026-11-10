internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText
internal import Testing

@testable import AskTUI

@Suite("Copying relative reply paths keeps selection coordinates but expands complete references")
struct ReplyPathCopyTests {
    private let display = PathDisplay(workspace: "/work/project", home: "/Users/me", ancestors: 2) {
        $0 == "/work/project/Sources/a.swift"
    }

    private func copy(_ text: String, range: Range<Int>? = nil, kind: Int = 0, reverse: Bool = false) -> String? {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        switch kind {
            case 1: transcript.addUser(text)
            case 2: transcript.addNotice(text, isError: false)
            default: transcript.addAssistantText(text)
        }
        let lines = TranscriptContent.hardLines(of: text)
        let start = ContentPosition(block: 0, line: 0, offset: range?.lowerBound ?? 0)
        let end = ContentPosition(block: 0, line: lines.count - 1, offset: range?.upperBound ?? lines.last!.count)
        return ReplyPathCopy.text(
            ContentSelection(anchor: reverse ? end : start, head: reverse ? start : end),
            in: transcript,
            display: display
        )
    }

    @Test func `a complete relative reference copies in full with its location and punctuation`() {
        #expect(copy("See Sources/a.swift:12:3, now.") == "See /work/project/Sources/a.swift:12:3, now.")
        #expect(copy("é Sources/a.swift", reverse: true) == "é /work/project/Sources/a.swift")
        #expect(
            copy("Sources/a.swift\nSources/a.swift") == "/work/project/Sources/a.swift\n/work/project/Sources/a.swift"
        )
    }

    @Test func `partial references, missing and refused paths stay as selected`() {
        #expect(copy("Sources/a.swift", range: 2 ..< 8) == "urces/")
        #expect(copy("Missing/a.swift ../private/a.swift") == "Missing/a.swift ../private/a.swift")
        #expect(copy("/already/full.swift") == "/already/full.swift")
    }

    @Test func `user text and code remain literal while notices expand references`() {
        #expect(copy("Sources/a.swift", kind: 1) == "Sources/a.swift")
        #expect(copy("Sources/a.swift", kind: 2) == "/work/project/Sources/a.swift")
        #expect(copy("`Sources/a.swift`") == "`Sources/a.swift`")
        #expect(copy("```swift\nSources/a.swift\n```") == "```swift\nSources/a.swift\n```")
        #expect(copy("[file](Sources/a.swift)") == "[file](Sources/a.swift)")
    }

    @Test(arguments: [true, false])
    func `both automatic copy and control C expand a selected rendered reference`(automatic: Bool) throws {
        var options = ScreenOptions.legacy
        options.copyOnSelect = automatic
        var rig = PointerRig(
            columns: 60,
            rows: 16,
            options: options,
            updates: [.assistantText("See Sources/a.swift now.")]
        )
        rig.controller.state.blocks.paths = display
        rig.draw()
        let row = try #require((0 ..< 16).first { rig.text(row: $0).contains("See Sources/a.swift now.") })
        let copied = rig.drag(from: (row, 0), to: (row, 23))
        let effects =
            automatic ? copied : rig.controller.handle(.key(KeyEvent(keyCode: 0x63, modifiers: .ctrl)), pageRows: 12)
        #expect(effects.contains(.copy("See /work/project/Sources/a.swift now.")))
    }

    @Test func `a selection across replies user text and tool output changes only reply references`() {
        var transcript = Transcript()
        transcript.setMarkdown(true)
        transcript.items = [
            .assistant("Sources/a.swift"), .user("Sources/a.swift"),
            .tool(name: "read", summary: "Sources/a.swift", status: .succeeded, output: "Sources/a.swift"),
            .notice("Sources/a.swift", isError: false)
        ]
        let selection = ContentSelection(
            anchor: ContentPosition(block: 0, line: 0, offset: 0),
            head: ContentPosition(block: 3, line: 0, offset: 15)
        )
        let original = selection.text(in: TranscriptContent(transcript)) ?? ""
        let expected =
            "/work/project/Sources/a.swift\n" + original.dropFirst(16).dropLast(15)
            + "/work/project/Sources/a.swift"
        #expect(ReplyPathCopy.text(selection, in: transcript, display: display) == expected)
    }

    @Test func `a summary and a host without path authority keep their source`() {
        var transcript = Transcript()
        transcript.addAssistantText("Sources/a.swift")
        transcript.summaryBlocks.insert(0)
        let selection = ContentSelection(
            anchor: ContentPosition(block: 0, line: 0, offset: 0),
            head: ContentPosition(block: 0, line: 0, offset: 15)
        )
        #expect(ReplyPathCopy.text(selection, in: transcript, display: display) == "Sources/a.swift")
        #expect(ReplyPathCopy.text(selection, in: transcript, display: nil) == "Sources/a.swift")
    }
}
