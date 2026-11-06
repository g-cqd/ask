internal import Foundation
internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// Note n11: a `/word` is drawn as a command only when it names one of ask's commands, and a click on it fills an empty input with it;
/// another single `/word` is plain text, unless a file at the root has that name.
@Suite("Only known commands are drawn as commands, and a click on one fills an empty input")
struct CommandLinkTests {
    private let commands: Set<String> = ["reload", "model"]

    @Test func `a known command is a command link, its arguments left out`() {
        let links = PathLinks.links(in: "Run /reload or /model fast.", home: "/h", commands: commands)
        #expect(
            links == [
                PathLinks.Link(columns: 4 ..< 11, uri: PathLinks.commandScheme + "reload"),
                PathLinks.Link(columns: 15 ..< 21, uri: PathLinks.commandScheme + "model")
            ]
        )
    }

    @Test func `an unknown single word is plain text, a root entry and a longer path stay files`() {
        #expect(PathLinks.links(in: "say /frobnicate-ask-0 now", home: "/h", commands: commands).isEmpty)
        #expect(PathLinks.links(in: "in /tmp now", home: "/h", commands: commands).map(\.uri) == ["file:///tmp"])
        #expect(PathLinks.links(in: "see /reload/x", home: "/h", commands: commands).map(\.uri) == ["file:///reload/x"])
    }

    @Test func `a command link is not sent to the terminal as a hyperlink`() {
        var line = ScreenComposer.Line(text: "/reload", style: .default)
        line.links = [PathLinks.Link(columns: 0 ..< 7, uri: PathLinks.commandScheme + "reload")]
        let spans = ScreenComposer.spans(of: line, highlight: nil)
        #expect(spans.count == 1 && spans[0].1.link == nil && spans[0].1.underline != .none, "\(spans)")
    }

    private func at(_ needle: String, in rig: PointerRig) -> (row: Int, col: Int)? {
        for row in 0 ..< rig.buffer.rows {
            let text = rig.text(row: row)
            if let range = text.range(of: needle) {
                return (row, text.distance(from: text.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    @Test func `a click on a command in the transcript fills the empty input, and leaves a written one alone`() throws {
        var rig = PointerRig(columns: 60, lines: ["Type /verbose to see more, not /frobnicate."])
        let cell = try #require(at("/verbose", in: rig))
        #expect(rig.controller.frame.links[cell.row].map(\.uri) == [PathLinks.commandScheme + "verbose"])
        #expect(rig.click(row: cell.row, col: cell.col + 2).isEmpty)
        #expect(rig.controller.state.editor.text == "/verbose ")
        rig.controller.state.editor.paste("half")
        _ = rig.click(row: cell.row, col: cell.col + 2)
        #expect(rig.controller.state.editor.text == "/verbose half")
    }
}
