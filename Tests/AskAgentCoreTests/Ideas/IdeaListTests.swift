import Foundation
import Testing

@testable import AskAgentCore

/// The ideas of roadmap 0180: kept verbatim with the time they were had, edited by the person, marked by the model, the new ones told
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
    func `an idea is kept as typed, with when it was had, and is new until marked`() throws {
        let list = try list(["  what if the sidebar\nfolded?  "])
        #expect(list.idea(1)?.text == "  what if the sidebar\nfolded?  ")
        #expect(list.idea(1)?.state == .new && list.newCount == 1)
        #expect(list.line(list.ideas[0], in: utc) == "i1 [new] 2026-11-01 14:05 what if the sidebar folded?")
    }

    @Test
    func `the model marks ideas, and the list shows what is still open, or everything`() throws {
        var list = try list(["one", "two", "three", "four"])
        try list.apply(.state(id: 2, .acknowledged))
        try list.apply(.state(id: 3, .fulfilled))
        try list.apply(.state(id: 4, .dismissed))
        #expect(list.newCount == 1)
        #expect(
            list.listing(all: false, in: utc) == """
                i1 [new] 2026-11-01 14:05 one
                i2 [acknowledged] 2026-11-01 14:06 two
                (2 fulfilled or dismissed, not shown)
                """
        )
        #expect(list.listing(all: true, in: utc).split(separator: "\n").count == 4)
        #expect(IdeaList().listing(all: false, in: utc) == "No ideas yet.")
    }

    @Test
    func `an edit replaces the text and says when, and a wrong id or an empty idea is refused`() throws {
        var list = try list(["first draft"])
        try list.apply(.edit(id: 1, text: "second draft", at: noon + 3600))
        #expect(list.idea(1)?.text == "second draft" && list.idea(1)?.edited == noon + 3600)
        let before = list
        #expect(throws: IdeaListError.unknownIdea(4)) { try list.apply(.state(id: 4, .fulfilled)) }
        #expect(throws: IdeaListError.emptyText) { try list.apply(.edit(id: 1, text: " \n", at: noon)) }
        #expect(throws: IdeaListError.emptyText) { try list.apply(list.adding("", at: noon)) }
        #expect(throws: IdeaListError.taken(1)) {
            try list.apply(.add(Idea(id: 1, text: "again", made: noon, edited: nil, state: .new)))
        }
        #expect(list == before)
    }

    @Test
    func `the slash command saves verbatim, lists, and edits by id`() throws {
        let list = try list(["keep it"])
        #expect(IdeaList.editing("i1 better words") == IdeaList.Edit(id: 1, text: "better words"))
        #expect(IdeaList.editing("i1") == IdeaList.Edit(id: 1, text: nil))
        #expect(
            IdeaList.editing("") == nil && IdeaList.editing("all") == nil && IdeaList.editing("idle thought") == nil
        )
        #expect(IdeaList.editing("x5 apples") == nil)
        #expect(list.draft(editing: 1) == "/ideas i1 keep it")
    }
}
