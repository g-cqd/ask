import Testing

@testable import AskTUI

/// The rule from roadmap 0048: a trigger fires only at the start of a word. A `/` or `@` inside a word (a path, an address)
/// is just text, and nothing else, `$` included, is a trigger.
@Suite("A trigger is a sigil at the start of the word under the cursor")
struct CompletionTriggerTests {
    private func trigger(_ text: String, cursor: Int? = nil, sigils: Set<Character> = ["/", "@"]) -> CompletionTrigger?
    {
        CompletionTrigger.at(cursor: cursor ?? text.count, in: text, sigils: sigils)
    }

    @Test func `a sigil that starts a word is a trigger, and the query is what follows it`() {
        #expect(trigger("/co") == CompletionTrigger(range: 0 ..< 3, query: "co"))
        #expect(trigger("please @fi") == CompletionTrigger(range: 7 ..< 10, query: "fi"))
        #expect(trigger("/") == CompletionTrigger(range: 0 ..< 1, query: ""))
    }

    @Test func `a sigil inside a word is just text`() {
        #expect(trigger("a/b") == nil)
        #expect(trigger("src/main.swift") == nil)
        #expect(trigger("me@host") == nil)
        #expect(trigger("x /usr/bin")?.query == "usr/bin")
    }

    @Test func `nothing but the sigils given is a trigger, and a dollar sign never is`() {
        #expect(trigger("$skill") == nil)
        #expect(trigger("#tag") == nil)
        #expect(trigger("@file", sigils: ["/"]) == nil)
        #expect(trigger("/cmd", sigils: ["@"]) == nil)
    }

    @Test func `a word ends at whitespace, a line break included`() {
        #expect(trigger("a\n/co") == CompletionTrigger(range: 2 ..< 5, query: "co"))
        #expect(trigger("/co now") == nil, "the cursor is in the second word")
        #expect(trigger("/co ") == nil, "the cursor is after the space, in no word")
    }

    @Test func `the whole word is replaced but the query stops at the cursor`() {
        #expect(trigger("/config", cursor: 4) == CompletionTrigger(range: 0 ..< 7, query: "con"))
        #expect(trigger("/config now", cursor: 2) == CompletionTrigger(range: 0 ..< 7, query: "c"))
    }

    @Test func `a cursor before the sigil is not in the word, and one right after it is`() {
        #expect(trigger("/co", cursor: 0) == nil)
        #expect(trigger("/co", cursor: 1) == CompletionTrigger(range: 0 ..< 3, query: ""))
    }

    @Test func `offsets count characters, so wide and combined graphemes are one each`() {
        #expect(trigger("/日本") == CompletionTrigger(range: 0 ..< 3, query: "日本"))
        #expect(trigger("/e\u{301}x") == CompletionTrigger(range: 0 ..< 3, query: "e\u{301}x"))
    }

    @Test func `an empty draft and a cursor past the end are no trigger and no crash`() {
        #expect(trigger("") == nil)
        #expect(trigger("/co", cursor: 99) == nil)
        #expect(trigger("/co", cursor: -1) == nil)
    }
}
