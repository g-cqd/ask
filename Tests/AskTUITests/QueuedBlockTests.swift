internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A queued message is dim, has no background, and starts with a spinner and the separator instead of a label (roadmap 0129).
@Suite("Queued messages and block hues")
struct QueuedBlockTests {
    private func running() -> ScreenController {
        var controller = ScreenController(label: "m", options: ScreenOptions())
        controller.handle(.userPrompt("go"))
        _ = controller.begin(.startRun("go"))
        return controller
    }

    @Test func `a queued message is a spinner, the separator and the text, dim and without a background`() throws {
        var controller = running()
        _ = controller.queue("then fix the tests", followUp: false)
        let rows = ScreenComposer.lines(
            in: controller.state.transcript, at: 1, columns: 40, style: controller.state.blocks)
        let row = try #require(rows.first { $0.text.contains("then fix") })
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        #expect(row.text.contains(frame + " · then fix the tests"))
        #expect(!row.text.contains("Queued"))
        #expect(row.style.dim && rows.allSatisfy { $0.style.bg == .default })
        #expect(row.source?.text == "then fix the tests", "a selection takes the text, not the mark")
    }

    @Test func `a long queued message hangs under its first word`() throws {
        var controller = running()
        _ = controller.queue(String(repeating: "word ", count: 12), followUp: true)
        let rows =
            ScreenComposer.lines(
                in: controller.state.transcript, at: 1, columns: 30, style: controller.state.blocks
            )
            .filter { !$0.text.allSatisfy(\.isWhitespace) }
        #expect(rows.count > 1)
        let lead = UnicodeWidth.displayWidth(of: String(try #require(rows.first?.text.prefix(4))))
        #expect(rows.dropFirst().allSatisfy { $0.text.hasPrefix(String(repeating: " ", count: lead)) })
        #expect(rows.allSatisfy { UnicodeWidth.displayWidth(of: $0.text) <= 30 })
    }

    @Test func `the spinner turns while it waits, and stops where the text went back to the editor`() {
        var controller = ScreenController(label: "m", options: ScreenOptions(interruptSendsQueued: .none))
        controller.handle(.userPrompt("go"))
        _ = controller.begin(.startRun("go"))
        _ = controller.queue("later", followUp: false)
        #expect(controller.hasLiveProgress)
        let before = controller.state.transcript.progress[1]?.frame
        controller.advanceProgress()
        #expect(controller.state.transcript.progress[1]?.frame == (before ?? 0) + 1)
        _ = controller.abort()
        controller.handle(.runEnded)
        #expect(controller.state.editor.text.contains("later"))
        let rows = ScreenComposer.lines(
            in: controller.state.transcript, at: 1, columns: 40, style: controller.state.blocks)
        #expect(rows.contains { $0.text.contains("↩ · later") })
        #expect(controller.state.transcript.progress[1]?.ended != nil)
    }

    @Test func `accepted, it becomes the user's block and its spinner is gone`() {
        var controller = running()
        _ = controller.queue("next", followUp: false)
        controller.advanceProgress()
        controller.handle(.promptAccepted(id: 0, text: "next"))
        #expect(controller.state.transcript.items.last == .user("next"))
        #expect(controller.state.transcript.progress[1] == nil)
    }

    /// How much bluer a colour is than the page, in channel units.
    private func blueness(_ color: Color, page: ScreenTheme.Page) -> Double {
        guard case .rgb(let r, let g, let b) = color else { return 0 }
        func tilt(_ r: Double, _ g: Double, _ b: Double) -> Double { b - (r + g) / 2 }
        return tilt(Double(r), Double(g), Double(b)) - tilt(page.background.x, page.background.y, page.background.z)
    }

    @Test func `the user's block is blue, bluer than a tool still running, which is grey, on light and dark pages`() {
        for page: ScreenTheme.Page in [
            .light, .dark, .init(background: SIMD3(0, 43, 54), foreground: SIMD3(131, 148, 150))
        ] {
            let theme = ScreenTheme(page: page)
            let user = blueness(theme.tint(for: .user("x")), page: page)
            let tool = blueness(
                theme.tint(for: .tool(name: "t", summary: "", status: .running, output: "")), page: page)
            #expect(user > tool + 3, "\(page): user \(user) against running tool \(tool)")
            #expect(abs(tool) <= 2, "\(page): a running tool is grey, not tinted by a hue (\(tool))")
        }
    }
}
