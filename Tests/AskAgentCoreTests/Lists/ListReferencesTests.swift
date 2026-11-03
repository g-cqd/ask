import Foundation
import Testing

@testable import AskAgentCore

/// Roadmap 0186: `#t3` and `#n2` in a message attach the task's or the note's text after it, each once, in order, as a skill's is.
@Suite("A task or a note named with # is attached to the message")
struct ListReferencesTests {
    private func lists() throws -> (TaskList, IdeaList) {
        var tasks = TaskList()
        try tasks.apply(tasks.adding(title: "write the parser", detail: "recursive descent"))
        try tasks.apply(tasks.adding(title: "ship it"))
        var ideas = IdeaList()
        try ideas.apply(ideas.adding("fold the sidebar\nwhen narrow", at: 0))
        return (tasks, ideas)
    }

    @Test func `named tasks and notes follow the message, each once, in order, and the views show the typed line`()
        throws
    {
        let (tasks, ideas) = try lists()
        let typed = "do #t2 after #t1, see #n1, and #t2 again."
        let sent = ListReferences.attach(typed, tasks: tasks, ideas: ideas)
        #expect(sent.hasPrefix(typed + "\n\n--- task t2 ---\nt2 [open] ship it\n--- end of task ---"))
        #expect(
            sent.contains("\n\n--- task t1 ---\nt1 [open] write the parser\n\nrecursive descent\n--- end of task ---")
        )
        #expect(sent.hasSuffix("--- note n1 ---\nfold the sidebar\nwhen narrow\n--- end of note ---"))
        #expect(sent.components(separatedBy: "--- task t2 ---").count == 2)
        #expect(SkillInvocation.shown(sent) == typed)
    }

    @Test func `an unknown id, a # inside a word, a bare number or no lists leave the message as typed`() throws {
        let (tasks, ideas) = try lists()
        for typed in ["see #t9", "a#t1", "issue #12", "(#t1)", "#tx", "plain"] {
            #expect(ListReferences.attach(typed, tasks: tasks, ideas: ideas) == typed, "\(typed)")
        }
        #expect(ListReferences.attach("see #t1", tasks: nil, ideas: nil) == "see #t1")
    }

    @Test func `references come after a skill's attachment, and only the typed line is read for them`() throws {
        let (tasks, ideas) = try lists()
        let withSkill = "do #t1 /skill:x\n\n--- skill x (agents, user) ---\nmentions #t2\n--- end of skill ---"
        let sent = ListReferences.attach(withSkill, tasks: tasks, ideas: ideas)
        #expect(sent.hasPrefix(withSkill + "\n\n--- task t1 ---"))
        #expect(!sent.contains("--- task t2 ---"))
    }
}
