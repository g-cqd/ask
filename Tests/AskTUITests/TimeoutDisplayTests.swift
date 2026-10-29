internal import Foundation
internal import Testing

@testable import AskTUI

/// `ui.timeout` and `ui.timeoutLabel` (roadmap 0126): by default a command's timeout is written only when the call chose one other than
/// the tool's default, so the common header is the tool and the command; `always` and `never` keep or drop it, and the word in front of
/// the duration is the person's, up to 8 cells.
@Suite("A command's timeout is written when it matters")
struct TimeoutDisplayTests {
    private let english = Locale(identifier: "en_US")
    private let usual = ToolCommand(timeout: .seconds(120), defaultTimeout: .seconds(120))
    private let longer = ToolCommand(timeout: .seconds(300), yield: .seconds(5), defaultTimeout: .seconds(120))

    private func text(_ command: ToolCommand, _ display: TimeoutDisplay, label: String = "timeout") -> String {
        command.parameters(localized: true, display: display, label: label, locale: english)
    }

    @Test func `auto leaves out the default timeout and writes any other`() {
        #expect(text(usual, .auto).isEmpty)
        #expect(text(longer, .auto) == "timeout 5 min · yield 5 sec")
        #expect(text(ToolCommand(timeout: .seconds(30)), .auto) == "timeout 30 sec", "no known default: written")
    }

    @Test func `always writes every timeout the call set, and never writes none`() {
        #expect(text(usual, .always) == "timeout 2 min")
        #expect(text(longer, .never).isEmpty)
        #expect(text(ToolCommand(), .always).isEmpty, "a call that set no limit has none to write")
    }

    @Test func `the label replaces the word, and is cut to 8 cells`() {
        #expect(text(longer, .auto, label: "⏱") == "⏱ 5 min · yield 5 sec")
        #expect(text(longer, .auto, label: "limite") == "limite 5 min · yield 5 sec")
        #expect(text(usual, .always, label: "全全全全全") == "全全全全 2 min", "10 cells cut to the 8 that fit")
    }

    @Test func `the transcript's header follows the setting, auto by default`() {
        var transcript = Transcript()
        #expect(transcript.timeoutDisplay == .auto)
        transcript.startTool(name: "shell", summary: "", id: "a", fullInput: "ls", command: usual)
        transcript.timeoutDisplay = .always
        transcript.timeoutLabel = "t"
        transcript.startTool(name: "shell", summary: "", id: "b", fullInput: "ls", command: usual)
        let summaries = transcript.items.compactMap { item -> String? in
            if case .tool(_, let summary, _, _, _) = item { return summary }
            return nil
        }
        #expect(summaries.count == 2)
        #expect(summaries.first == "")
        #expect(summaries.last?.hasPrefix("t ") == true)
    }

    @Test func `the screen options carry both settings into the transcript`() {
        var options = ScreenOptions()
        #expect(options.timeoutDisplay == .auto && options.timeoutLabel == "timeout")
        options.timeoutDisplay = .never
        options.timeoutLabel = "⏱"
        let controller = ScreenController(label: "t", options: options)
        #expect(controller.state.transcript.timeoutDisplay == .never)
        #expect(controller.state.transcript.timeoutLabel == "⏱")
    }
}
