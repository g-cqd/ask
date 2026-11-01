import Foundation
import TerminalKitStyle
import TerminalKitText
import Testing

@testable import AskTUI

/// An open tool block whose output is long keeps the output's head and tail, with a marker between them (roadmap 0078).
@Suite("A long tool output folds its middle")
struct ToolOutputFoldTests {
    private static let output = (1 ... 300).map { "out \($0)" }.joined(separator: "\n")

    private func transcript(lines: Int = 10) -> Transcript {
        var result = Transcript()
        result.startTool(name: "shell", summary: "seq", id: "call", fullInput: "seq 300")
        result.finishTool(.succeeded, output: Self.output, id: "call")
        result.setToolsFoldedByDefault(false)
        result.setOutputFoldLimits(lines: lines, bytes: 1 << 20)
        return result
    }

    private func texts(_ transcript: Transcript) -> [String] {
        ScreenComposer.lines(in: transcript, at: 0, columns: 80).map { $0.text.trimmingCharacters(in: .whitespaces) }
    }

    @Test func `the head and tail are drawn with a marker between them, and the header counts every line`() throws {
        let rows = ScreenComposer.lines(in: transcript(), at: 0, columns: 80)
        let shown = rows.map { $0.text.trimmingCharacters(in: .whitespaces) }
        #expect(shown.first?.contains("300 lines") == true)
        let marker = try #require(shown.firstIndex { $0.hasPrefix("⋯ 290 lines hidden") })
        #expect(shown[marker - 1] == "out 5")
        #expect(shown[marker + 1] == "out 296")
        #expect(!shown.contains("out 6") && !shown.contains("out 295"))
        #expect(rows[marker].source == nil, "the marker is not text a selection takes")
        #expect(rows[marker].style.dim)
    }

    @Test func `the copied text has the head and the tail, without the middle or the marker`() {
        let text = transcript().contentText(at: 0)
        #expect(text.contains("out 5\nout 296"))
        #expect(!text.contains("out 6\n") && !text.contains("hidden"))
    }

    @Test func `toggling the output fold shows the whole output and keeps the marker to fold it again`() throws {
        var transcript = transcript()
        transcript.toggleCodeFold(Transcript.outputFence, at: 0)
        let shown = texts(transcript)
        #expect(shown.contains("out 150"))
        let marker = try #require(shown.firstIndex { $0.hasPrefix("⋯ 290 lines shown") })
        #expect(shown[marker - 1] == "out 5" && shown[marker + 1] == "out 6")
        #expect(transcript.contentText(at: 0).contains(Self.output))
        #expect(!transcript.isFolded(0))
    }

    @Test func `output within the limits has no marker`() {
        let shown = texts(transcript(lines: 300))
        #expect(shown.contains("out 150"))
        #expect(!shown.contains { $0.hasPrefix("⋯") })
    }

    @Test func `Ctrl+G opens the middle of every long output, and folds it again`() {
        var transcript = transcript()
        transcript.setCodeFoldedByDefault(false)
        #expect(texts(transcript).contains("out 150"))
        transcript.setCodeFoldedByDefault(true)
        #expect(!texts(transcript).contains("out 150"))
        #expect(!transcript.isFolded(0))
    }

    @Test func `a click on the marker opens the middle, not the whole block`() throws {
        var rig = PointerRig(
            columns: 80,
            rows: 340,
            updates: [
                .toolStarted(name: "shell", summary: "seq", id: "call", fullInput: "seq 300"),
                .toolFinished(.succeeded, output: Self.output, id: "call")
            ]
        )
        rig.controller.state.transcript.setToolsFoldedByDefault(false)
        rig.controller.state.transcript.setOutputFoldLimits(lines: 10, bytes: 1 << 20)
        rig.draw()
        let marker = try #require((0 ..< 340).first { rig.text(row: $0).contains("lines hidden") })
        _ = rig.click(row: marker, col: 4)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect(rig.controller.state.transcript.contentText(at: 0).contains("out 150"))
        rig.draw()
        let open = try #require((0 ..< 340).first { rig.text(row: $0).contains("lines shown") })
        _ = rig.click(row: open, col: 4)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect(!rig.controller.state.transcript.contentText(at: 0).contains("out 150"))
    }
}
