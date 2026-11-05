import Testing

@testable import AskTUI

/// Where a subagent starts (roadmap 0063, ADR-0146): its block says the model started it with only its task, not that it was forked
/// with the conversation, as a thread's says.
@Suite("A subagent's block says what it was given")
struct SubagentBlockTests {
    private func text(_ update: ConversationUpdate) -> String {
        var transcript = Transcript()
        transcript.addThreadBlock(update)
        return (0 ..< transcript.items.count).map { transcript.contentText(at: $0) }.joined(separator: "\n")
            + transcript.items.map { "\($0)" }.joined()
    }

    @Test func `a subagent's start says it has only its task; a thread's that it was forked`() {
        let subagent = text(.threadStarted(id: "fork-thread-2", name: "thread-2", prompt: "find it", subagent: true))
        #expect(subagent.contains("subagent") && subagent.contains("only its task") && !subagent.contains("forked"))
        let thread = text(.threadStarted(id: "fork-thread-1", name: "thread-1", prompt: "look"))
        #expect(thread.contains("forked from this point"))
    }
}
