internal import Testing

@testable import AskTUI

/// The workspace's git state at the end of the status bar (roadmap 0186; the owner, 2026-11-12). Narrow, it shortens, then is the
/// branch alone, then goes, before the folder does.
@Suite("The status line ends with the workspace's git state")
struct StatusGitTests {
    private func state(_ forms: [String]) -> ScreenState {
        var controller = ScreenController(label: "claude-5")
        controller.state.context = "12%"
        _ = controller.handle(.gitStatus(forms))
        return controller.state
    }

    private func text(_ state: ScreenState, columns: Int = 200) -> String {
        ScreenComposer.status(for: state, columns: columns).line.text
    }

    @Test func `at the end, and shorter as the line narrows`() {
        let git = state(["main ↑2 ↓1 · 3 changed", "main ↑2↓1 ·3", "main"])
        let mark = ScreenComposer.leadingMark(for: git).character
        let full = "\(mark) · claude-5 · 12% · main ↑2 ↓1 · 3 changed"
        #expect(text(git) == full)
        #expect(text(git, columns: full.count - 1) == "\(mark) · claude-5 · 12% · main ↑2↓1 ·3")
        #expect(text(git, columns: "\(mark) · claude-5 · 12% · main".count) == "\(mark) · claude-5 · 12% · main")
        #expect(text(git, columns: "\(mark) · claude-5 · 12%".count) == "\(mark) · claude-5 · 12%")
    }

    @Test func `outside a repository there is nothing`() {
        let none = state([])
        let mark = ScreenComposer.leadingMark(for: none).character
        #expect(text(none) == "\(mark) · claude-5 · 12%")
    }

    @Test func `the branch's pull request follows the git state in every form, and goes with it`() {
        var controller = ScreenController(label: "claude-5")
        controller.state.context = "12%"
        _ = controller.handle(.gitStatus(["main · 3 changed", "main ·3", "main"]))
        _ = controller.handle(.branchPullRequest(42))
        let mark = ScreenComposer.leadingMark(for: controller.state).character
        #expect(text(controller.state) == "\(mark) · claude-5 · 12% · main · 3 changed · #42")
        let short = "\(mark) · claude-5 · 12% · main #42"
        #expect(text(controller.state, columns: short.count) == short)
        _ = controller.handle(.branchPullRequest(nil))
        #expect(text(controller.state) == "\(mark) · claude-5 · 12% · main · 3 changed")
    }
}
