internal import Testing

@testable import AskTUI

/// `ui.historyLimit` (note n29; the owner, 2026-11-06 and 2026-11-11): unlimited by default; past N blocks the oldest leave the
/// screen and its memory, a line says how many, and a block still going stays. The session file keeps everything.
@Suite("ui.historyLimit keeps the screen to the last blocks")
struct HistoryLimitTests {
    private func limited(_ limit: Int?) -> Transcript {
        var transcript = Transcript()
        transcript.history.limit = limit
        return transcript
    }

    private func text(_ transcript: Transcript, _ index: Int) -> String {
        ScreenComposer.lines(in: transcript, at: index, columns: 80).map(\.text).joined(separator: "\n")
    }

    @Test func `unlimited by default`() {
        var transcript = Transcript()
        for number in 1 ... 50 { transcript.addNotice("n\(number)", isError: false) }
        #expect(transcript.history.limit == nil && transcript.history.trimmed == 0)
        #expect(!transcript.items.contains(.trimmed))
    }

    @Test func `past the limit the oldest go, and the newest gone says how many`() {
        var transcript = limited(3)
        for number in 1 ... 5 { transcript.addNotice("n\(number)", isError: false) }
        #expect(transcript.items[0] == .trimmed && transcript.items[1] == .trimmed)
        #expect(
            Array(transcript.items.dropFirst(2)) == [
                .notice("n3", isError: false), .notice("n4", isError: false), .notice("n5", isError: false)
            ]
        )
        #expect(transcript.history.trimmed == 2)
        #expect(text(transcript, 0).isEmpty)
        #expect(text(transcript, 1).contains("2 earlier blocks are not shown (ui.historyLimit)"))
        transcript.addNotice("n6", isError: false)
        #expect(text(transcript, 1).isEmpty, "only the newest gone says so")
        #expect(text(transcript, 2).contains("3 earlier blocks are not shown"))
    }

    @Test func `what a gone block held is forgotten, and a late update for it changes nothing`() {
        var transcript = limited(1)
        transcript.startTool(name: "bash", summary: "ls", id: "a", fullInput: "ls", command: ToolCommand())
        transcript.finishTool(.succeeded, output: "a\nb", id: "a")
        transcript.addNotice("later", isError: false)
        #expect(transcript.items[0] == .trimmed)
        #expect(transcript.toolBlocks["a"] == nil && transcript.commandBlocks.isEmpty && transcript.progress[0] == nil)
        transcript.finishTool(.failed("late"), output: "late", id: "a")
        #expect(transcript.items[0] == .trimmed)
    }

    @Test func `a block still going stays`() {
        var transcript = limited(1)
        transcript.startTool(name: "bash", summary: "make", id: "a", fullInput: "make", command: ToolCommand())
        transcript.addNotice("one", isError: false)
        transcript.addNotice("two", isError: false)
        #expect(transcript.items[0] != .trimmed, "the running tool")
        #expect(transcript.items[1] == .trimmed && transcript.items[2] == .notice("two", isError: false))
    }

    @Test func `a cleared conversation starts again, and a thread's lane has the same limit`() {
        var transcript = limited(2)
        for number in 1 ... 4 { transcript.addNotice("n\(number)", isError: false) }
        transcript.removeAll()
        #expect(transcript.history.trimmed == 0 && transcript.history.limit == 2)
        #expect(transcript.emptyLike(revisionBase: 1_000).history.limit == 2)
    }

    @Test func `the screen takes it from its options`() {
        var options = ScreenOptions()
        #expect(options.historyLimit == nil)
        options.historyLimit = 7
        #expect(ScreenController(label: "m", options: options).state.transcript.history.limit == 7)
    }
}
