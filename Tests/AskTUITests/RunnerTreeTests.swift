import Testing

@testable import AskTUI

@Suite("Runner snapshots have one stable preorder, even with missing parents, cycles and repeated ids")
struct RunnerTreeTests {
    private func node(_ id: String, parent: String? = nil, state: RunnerInfo.State = .running) -> RunnerInfo {
        RunnerInfo(name: id, detail: "work", parentID: parent, state: state)
    }

    @Test func `parents precede children and siblings retain supplied order even with child first`() {
        let tree = RunnerTree([
            node("grandchild", parent: "child"), node("other"), node("parent"),
            node("child", parent: "parent"), node("sibling", parent: "parent")
        ])
        #expect(tree.rows.map(\.runner.id) == ["other", "parent", "child", "grandchild", "sibling"])
        #expect(tree.rows.map(\.depth) == [0, 0, 1, 2, 1])
    }

    @Test func `a missing or self parent is a root and a repeated id is shown once with its first value`() {
        let tree = RunnerTree([node("orphan", parent: "gone"), node("self", parent: "self"), node("orphan")])
        #expect(tree.rows.map(\.runner.id) == ["orphan", "self"])
        #expect(tree.rows.map(\.depth) == [0, 0])
        #expect(tree.runners.first?.parentID == "gone")
        #expect(tree.activeCount == 2)
    }

    @Test func `cycles and their descendants are not lost and never appear twice`() {
        let tree = RunnerTree([node("a", parent: "b"), node("b", parent: "a"), node("c", parent: "a")])
        #expect(tree.rows.map(\.runner.id) == ["a", "b", "c"])
        #expect(tree.rows.map(\.depth) == [0, 1, 1])
    }

    @Test func `a deep tree uses no recursion and retains the depth of every row`() {
        let nodes = (0 ..< 10_000).map { node("n\($0)", parent: $0 == 0 ? nil : "n\($0 - 1)") }
        let tree = RunnerTree(nodes)
        #expect(tree.rows.count == 10_000)
        #expect(tree.rows.last?.depth == 9_999)
    }

    @Test func `only running and waiting nodes count as active while terminal states remain in the tree`() {
        var state = ScreenState(label: "m")
        state.runners = [
            node("a"), node("b", state: .waitingForApproval), node("c", state: .done),
            node("d", state: .failed), node("e", state: .stopped)
        ]
        state.runnersOpen = true
        #expect(state.runnerTree.activeCount == 2)
        #expect(ScreenComposer.status(for: state).line.text == "m · ready · 2 jobs")
        let rows = ScreenComposer.runnerRows(for: state, available: 20, columns: 100).map(\.text)
        #expect(
            rows == [
                "a  work · running", "b  work · waiting for approval", "c  work · done",
                "d  work · failed", "e  work · stopped"
            ])
    }

    @Test func `the status counts agents as runners and the strip and count come from the same deduplicated tree`() {
        var state = ScreenState(label: "m")
        let agent = RunnerInfo(name: "review", detail: "reading", kind: .agent)
        state.runners = [agent, agent, node("job", parent: "review")]
        state.runnersOpen = true
        #expect(ScreenComposer.status(for: state).line.text == "m · ready · 2 runners")
        #expect(
            ScreenComposer.runnerRows(for: state, available: 10, columns: 100).map(\.text)
                == ["review  reading · running", "  job  work · running"])
    }

    @Test func `an empty tree has no rows or active count`() {
        let tree = RunnerTree()
        #expect(tree.runners.isEmpty && tree.rows.isEmpty && tree.activeCount == 0)
    }
}
