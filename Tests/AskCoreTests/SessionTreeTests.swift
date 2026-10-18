import Testing

@testable import AskCore

@Suite("Session branches and context")
struct SessionTreeTests {
    @Test func `an empty session has no leaf or context`() {
        let tree = SessionTree()
        #expect(tree.leaf == nil)
        #expect(tree.entries.isEmpty)
        #expect(tree.context().isEmpty)
    }

    @Test func `append links each entry to the selected leaf`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("one"))
        let child = try tree.append(.assistant("two"))
        #expect(tree.leaf == child)
        #expect(tree.entry(root)?.parentID == nil)
        #expect(tree.entry(child)?.parentID == root)
        #expect(tree.activeBranch().map(\.id) == [root, child])
    }

    @Test func `a branch leaves abandoned entries intact but out of context`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("one"))
        let abandoned = try tree.append(.assistant("abandoned"))
        let branch = try tree.continuing(from: root, with: .user("kept"))
        #expect(tree.entry(abandoned)?.payload == .assistant("abandoned"))
        #expect(tree.context().map(\.id) == [root, branch])
        #expect(tree.count == 3)
    }

    @Test func `selecting an earlier entry does not truncate history`() throws {
        var tree = SessionTree()
        let first = try tree.append(.user("one"))
        let second = try tree.append(.assistant("two"))
        try tree.moveLeaf(to: first)
        #expect(tree.context().map(\.id) == [first])
        #expect(tree.entry(second) != nil)
    }

    @Test func `a new root can be selected without deleting old roots`() throws {
        var tree = SessionTree()
        let old = try tree.append(.user("old root"))
        try tree.moveLeaf(to: nil)
        let new = try tree.append(.user("new root"))
        #expect(tree.entry(new)?.parentID == nil)
        #expect(tree.context().map(\.id) == [new])
        #expect(tree.entry(old) != nil)
    }

    @Test func `an unknown branch parent fails without moving the leaf`() throws {
        var tree = SessionTree()
        _ = try tree.append(.user("original"))
        let before = tree
        #expect(throws: SessionTreeError.unknownEntry(EntryID("missing"))) {
            try tree.continuing(from: EntryID("missing"), with: .user("lost"))
        }
        #expect(tree == before)
    }

    @Test func `an unknown checkout fails without changing the tree`() throws {
        var tree = SessionTree()
        _ = try tree.append(.user("original"))
        let before = tree
        #expect(throws: SessionTreeError.unknownEntry(EntryID("missing"))) {
            try tree.moveLeaf(to: EntryID("missing"))
        }
        #expect(tree == before)
    }

    @Test func `context starts with the actual compaction then retained messages and new turns`() throws {
        var tree = SessionTree()
        let old = try tree.append(.user("old"))
        let kept = try tree.append(.assistant("retain"))
        let summary = try tree.append(.compaction(summary: "checkpoint", firstKept: kept))
        let after = try tree.append(.user("new"))
        #expect(tree.context().map(\.id) == [summary, kept, after])
        #expect(
            tree.context().map(\.payload) == [
                .compaction(summary: "checkpoint", firstKept: kept), .assistant("retain"), .user("new")
            ])
        #expect(tree.entry(old)?.payload == .user("old"))
        #expect(tree.count == 4)
    }

    @Test func `compaction can retain the root`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("retain root"))
        let summary = try tree.append(.compaction(summary: "summary", firstKept: root))
        #expect(tree.context().map(\.id) == [summary, root])
    }

    @Test func `only the latest compaction on the active branch contributes a summary`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        _ = try tree.append(.compaction(summary: "older", firstKept: root))
        let kept = try tree.append(.user("retained"))
        let summary = try tree.append(.compaction(summary: "latest", firstKept: kept))
        #expect(tree.context().map(\.id) == [summary, kept])
        #expect(tree.count == 4)
    }

    @Test func `an older compaction inside the retained range is not replayed`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        _ = try tree.append(.compaction(summary: "older", firstKept: root))
        let middle = try tree.append(.assistant("middle"))
        let latest = try tree.append(.compaction(summary: "latest", firstKept: root))
        #expect(tree.context().map(\.id) == [latest, root, middle])
    }

    @Test func `a compaction cannot keep another compaction`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        let summary = try tree.append(.compaction(summary: "first", firstKept: root))
        let before = tree
        #expect(throws: SessionTreeError.invalidCompactionBoundary(summary)) {
            try tree.append(.compaction(summary: "second", firstKept: summary))
        }
        #expect(tree == before)
    }

    @Test(arguments: ["", String(repeating: "x", count: 129)])
    func `restoring rejects empty and oversized identifiers`(raw: String) throws {
        let entry = SessionEntry(id: EntryID(raw), parentID: nil, payload: .user("one"))
        #expect(throws: SessionTreeError.invalidIdentifier(entry.id)) {
            try SessionTree(entries: [entry], leaf: nil)
        }
    }

    @Test func `restoring rejects a leaf that is not in the archive`() throws {
        let entry = SessionEntry(id: EntryID("a"), parentID: nil, payload: .user("one"))
        #expect(throws: SessionTreeError.unknownEntry(EntryID("z"))) {
            try SessionTree(entries: [entry], leaf: EntryID("z"))
        }
    }

    @Test func `a compaction on another branch cannot change this branch's context`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        _ = try tree.append(.compaction(summary: "other branch", firstKept: root))
        let child = try tree.continuing(from: root, with: .assistant("ours"))
        #expect(tree.context().map(\.id) == [root, child])
    }

    @Test func `a compaction boundary must be on its own ancestry`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        let foreign = try tree.append(.user("foreign"))
        try tree.moveLeaf(to: root)
        let before = tree
        #expect(throws: SessionTreeError.invalidCompactionBoundary(foreign)) {
            try tree.append(.compaction(summary: "invalid", firstKept: foreign))
        }
        #expect(tree == before)
    }

    @Test func `a failed compacting branch leaves its original selection intact`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        let tip = try tree.append(.user("tip"))
        let before = tree
        #expect(throws: SessionTreeError.invalidCompactionBoundary(tip)) {
            try tree.continuing(from: root, with: .compaction(summary: "bad", firstKept: tip))
        }
        #expect(tree == before)
    }

    @Test func `restoring rejects duplicate identifiers`() throws {
        let entry = SessionEntry(id: EntryID("a"), parentID: nil, payload: .user("one"))
        #expect(throws: SessionTreeError.duplicateEntry(entry.id)) {
            try SessionTree(entries: [entry, entry], leaf: entry.id)
        }
    }

    @Test func `restoring rejects parents that have not appeared yet`() throws {
        let entry = SessionEntry(id: EntryID("a"), parentID: EntryID("b"), payload: .user("one"))
        #expect(throws: SessionTreeError.unknownEntry(EntryID("b"))) {
            try SessionTree(entries: [entry], leaf: entry.id)
        }
    }

    @Test func `a restored tree cannot overwrite an existing sparse identifier`() throws {
        let first = SessionEntry(id: EntryID("1"), parentID: nil, payload: .user("saved"))
        var tree = try SessionTree(entries: [first], leaf: first.id)
        let next = try tree.append(.user("new"))
        #expect(next != first.id)
        #expect(tree.entry(first.id) == first)
    }

    @Test func `fork keeps only the selected path and preserves identifiers`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        let other = try tree.append(.assistant("other"))
        let chosen = try tree.continuing(from: root, with: .assistant("chosen"))
        let fork = try tree.fork()
        #expect(fork.entries.map(\.id) == [root, chosen])
        #expect(fork.leaf == chosen)
        #expect(fork.entry(other) == nil)
        #expect(tree.entry(other) != nil)
    }

    @Test func `mutating a copy leaves the original session unchanged`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        var copy = tree
        _ = try copy.append(.assistant("copy only"))
        #expect(tree.leaf == root)
        #expect(tree.count == 1)
        #expect(copy.count == 2)
    }
}
