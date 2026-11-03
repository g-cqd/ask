import Foundation
import Testing

@testable import AskAgentCore

/// The notes of roadmap 0180: kept verbatim with the time they were had, edited or deleted by the person, marked by the model, the new ones told
/// apart.
@Suite
struct IdeaListTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-01 14:05 UTC.
    private let noon = 1_793_541_900

    private func list(_ texts: [String]) throws -> IdeaList {
        var list = IdeaList()
        for (index, text) in texts.enumerated() { try list.apply(list.adding(text, at: noon + index * 60)) }
        return list
    }

    @Test
    func `a note is kept as typed, with when it was had, and is new until marked`() throws {
        let list = try list(["  what if the sidebar\nfolded?  "])
        #expect(list.idea(1)?.text == "  what if the sidebar\nfolded?  ")
        #expect(list.idea(1)?.state == .new && list.newCount == 1)
        #expect(list.line(list.ideas[0], in: utc) == "n1 [new] 2026-11-01 14:05 what if the sidebar folded?")
    }

    @Test
    func `the model marks notes, and the list shows what is still open, or everything`() throws {
        var list = try list(["one", "two", "three", "four"])
        try list.apply(.state(id: 2, .acknowledged))
        try list.apply(.state(id: 3, .fulfilled))
        try list.apply(.state(id: 4, .dismissed))
        #expect(list.newCount == 1)
        #expect(
            list.listing(all: false, in: utc) == """
                n1 [new] 2026-11-01 14:05 one
                n2 [acknowledged] 2026-11-01 14:06 two
                (2 fulfilled or dismissed, not shown)
                """
        )
        #expect(list.listing(all: true, in: utc).split(separator: "\n").count == 4)
        #expect(IdeaList().listing(all: false, in: utc) == "No notes yet.")
    }

    @Test
    func `an edit replaces the text and says when, a delete removes it, and a wrong id or an empty note is refused`()
        throws
    {
        var list = try list(["first draft", "second note"])
        try list.apply(.edit(id: 1, text: "second draft", at: noon + 3600))
        #expect(list.idea(1)?.text == "second draft" && list.idea(1)?.edited == noon + 3600)
        try list.apply(.remove(id: 2))
        #expect(list.idea(2) == nil && list.ideas.count == 1)
        let before = list
        #expect(throws: IdeaListError.unknownIdea(4)) { try list.apply(.state(id: 4, .fulfilled)) }
        #expect(throws: IdeaListError.unknownIdea(2)) { try list.apply(.remove(id: 2)) }
        #expect(throws: IdeaListError.emptyText) { try list.apply(.edit(id: 1, text: " \n", at: noon)) }
        #expect(throws: IdeaListError.emptyText) { try list.apply(list.adding("", at: noon)) }
        #expect(throws: IdeaListError.taken(1)) {
            try list.apply(.add(Idea(id: 1, text: "again", made: noon, edited: nil, state: .new)))
        }
        #expect(list == before)
    }

    @Test
    func `the slash command parses add, list, show, edit, delete, and search`() throws {
        let list = try list(["keep it", "sidebar folding"])
        #expect(IdeaList.parse(command: "notes", arguments: "") == .list(all: false))
        #expect(IdeaList.parse(command: "notes", arguments: "all") == .list(all: true))
        #expect(IdeaList.parse(command: "notes:all", arguments: "") == .list(all: true))
        #expect(IdeaList.parse(command: "notes", arguments: "n1") == .show(1))
        #expect(IdeaList.parse(command: "notes:show", arguments: "n1") == .show(1))
        #expect(IdeaList.parse(command: "notes:edit", arguments: "n1") == .edit(IdeaList.Edit(id: 1, text: nil)))
        #expect(
            IdeaList.parse(command: "notes:edit", arguments: "n1 better words")
                == .edit(IdeaList.Edit(id: 1, text: "better words"))
        )
        #expect(IdeaList.parse(command: "notes:delete", arguments: "n1") == .delete(1))
        #expect(IdeaList.parse(command: "notes:search", arguments: "sidebar") == .search("sidebar"))
        #expect(IdeaList.parse(command: "notes", arguments: "a new thought") == .add("a new thought"))
        #expect(IdeaList.parse(command: "notes:add", arguments: "a new thought") == .add("a new thought"))
        #expect(list.draft(editing: 1) == "/notes:edit n1 keep it")
        #expect(list.searching("sidebar", in: utc) == "n2 [new] 2026-11-01 14:06 sidebar folding")
    }
}
