import Testing

@testable import AskTUI

/// An edit's header says how many occurrences it replaced, from the count the tool reported, not from its sentence
/// (roadmap 0078): on the right, where a read counts the lines it returned.
@Suite("An edit's header counts its replacements")
struct EditReplacementHeaderTests {
    private func header(_ replacements: Int?, output: String = "Replaced it.") -> String {
        var controller = ScreenController(label: "test", options: ScreenOptions())
        _ = controller.begin(.startRun("go"))
        _ = controller.apply(.toolStarted(name: "edit", summary: "a.txt", id: "e"))
        _ = controller.apply(.toolFinished(.succeeded, output: output, id: "e", replacements: replacements))
        let index = controller.state.transcript.items.lastIndex {
            if case .tool = $0 { true } else { false }
        }
        return index.map {
            ScreenComposer.lines(in: controller.state.transcript, at: $0, columns: 80).first?.text ?? ""
        }
            ?? ""
    }

    @Test func `the reported count is shown beside the status, singular for one`() {
        #expect(header(3).hasSuffix("3 replacements · ✓"))
        #expect(header(1).hasSuffix("1 replacement · ✓"))
        #expect(header(3).contains("edit · a.txt "), "the target is left as it was")
    }

    @Test func `no count is made up from the result's sentence`() {
        #expect(!header(nil, output: "Replaced 3 occurrences in a.txt.").contains("replacement"))
    }
}
