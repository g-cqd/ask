import Testing

@testable import AskAgentCore

/// A session's prompts as numbered turns, so a person can go back to before one (`/tree N`, ADR-0093). Numbers follow the order the
/// prompts were recorded, which never changes, so a number read in a listing still means that prompt when it is used.
@Suite("A session outline numbers its prompts and says which branch each is on")
struct SessionOutlineTests {
    /// user 1, reply, user 2, reply: a straight conversation.
    private func straight() throws -> (tree: SessionTree, ids: [EntryID]) {
        var tree = SessionTree()
        let ids = [
            try tree.append(.user("fix the parser")), try tree.append(.assistant("done")),
            try tree.append(.user("now add tests")), try tree.append(.assistant("added"))
        ]
        return (tree, ids)
    }

    @Test
    func `a straight conversation is numbered in order, every turn on the path, each following the entry before it`()
        throws
    {
        let (tree, ids) = try straight()
        let outline = SessionOutline(tree)
        #expect(outline.turns.map(\.number) == [1, 2])
        #expect(outline.turns.map(\.text) == ["fix the parser", "now add tests"])
        #expect(outline.turns.map(\.isOnActiveBranch) == [true, true])
        #expect(outline.turns.map(\.before) == [nil, ids[1]])
        #expect(outline.turns.map(\.follows) == [.first, .first])
    }

    @Test func `only prompts are turns: replies, tool results and compactions are not`() throws {
        var tree = SessionTree()
        let first = try tree.append(.user("a"))
        try tree.append(.assistant("r"))
        try tree.append(.toolResult(callID: "t", content: "x", isError: false))
        try tree.append(.compaction(summary: "s", firstKept: first))
        try tree.append(.user("b"))
        #expect(SessionOutline(tree).turns.map(\.text) == ["a", "b"])
    }

    @Test
    func `a prompt sent after going back is a branch after the prompt it replaced, and the old one leaves the path`()
        throws
    {
        var (tree, ids) = try straight()
        try tree.moveLeaf(to: ids[1])  // back to before "now add tests"
        try tree.append(.user("use Swift Testing"))
        let outline = SessionOutline(tree)
        #expect(outline.turns.map(\.number) == [1, 2, 3])
        #expect(outline.turns.map(\.isOnActiveBranch) == [true, false, true])
        #expect(outline.turns.map(\.follows) == [.first, .first, .branch(after: 1)])
        #expect(outline.turns[2].before == ids[1])
    }

    @Test func `numbers do not change when a branch is added later, so a listing stays good`() throws {
        var (tree, ids) = try straight()
        let before = SessionOutline(tree).turns.map(\.text)
        try tree.moveLeaf(to: ids[1])
        try tree.append(.user("another"))
        #expect(Array(SessionOutline(tree).turns.map(\.text).prefix(2)) == before)
    }

    @Test func `a prompt that starts again from nothing is a branch after no prompt`() throws {
        var (tree, _) = try straight()
        try tree.moveLeaf(to: nil)
        try tree.append(.user("from scratch"))
        let outline = SessionOutline(tree)
        #expect(outline.turns[2].follows == .branch(after: nil) && outline.turns[2].before == nil)
        #expect(outline.turns.map(\.isOnActiveBranch) == [false, false, true])
    }

    @Test func `two prompts in a row follow each other, and the second names the first as what it follows`() throws {
        var tree = SessionTree()
        let first = try tree.append(.user("one"))
        try tree.append(.user("two"))
        #expect(SessionOutline(tree).turns.map(\.before) == [nil, first])
    }

    @Test func `a branch after a reply to a later prompt names that prompt's number`() throws {
        var (tree, ids) = try straight()
        try tree.moveLeaf(to: ids[3])  // after the last reply
        try tree.append(.user("third"))
        try tree.moveLeaf(to: ids[3])
        try tree.append(.user("third, differently"))
        #expect(SessionOutline(tree).turns.map(\.follows) == [.first, .first, .first, .branch(after: 2)])
    }

    @Test func `looking a turn up by number, and by a number that is not there`() throws {
        let outline = SessionOutline(try straight().tree)
        #expect(outline.turn(2)?.text == "now add tests")
        #expect(outline.turn(0) == nil && outline.turn(3) == nil && outline.turn(-1) == nil)
    }

    @Test func `the listing marks the path, names branches, and cuts a long first line`() throws {
        var (tree, ids) = try straight()
        try tree.moveLeaf(to: ids[1])
        try tree.append(.user("use Swift Testing\nand run it twice " + String(repeating: "x", count: 100)))
        let lines = SessionOutline(tree).lines(textLimit: 30)
        #expect(lines.count == 3)
        #expect(lines[0] == "> 1  fix the parser")
        #expect(lines[1] == "  2  now add tests")
        #expect(lines[2].hasPrefix("> 3  use Swift Testing and run it ") && lines[2].hasSuffix("…  (branch after 1)"))
    }

    @Test func `numbers line up when there are ten or more turns`() throws {
        var tree = SessionTree()
        for number in 1 ... 10 {
            try tree.append(.user("prompt \(number)"))
            try tree.append(.assistant("reply"))
        }
        let lines = SessionOutline(tree).lines()
        #expect(lines[0] == ">  1  prompt 1" && lines[9] == "> 10  prompt 10")
    }

    @Test func `an empty session has no turns and no listing`() {
        #expect(SessionOutline(SessionTree()).turns.isEmpty && SessionOutline(SessionTree()).lines().isEmpty)
    }
}
