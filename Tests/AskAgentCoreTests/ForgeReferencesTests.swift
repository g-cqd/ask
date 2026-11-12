import Testing

@testable import AskAgentCore

/// `#123` in a message (roadmap 0186): the pull request's or issue's title, state and body, attached after what was typed, as a task is;
/// read from the workspace's GitHub repository, with `GITHUB_TOKEN` for a private one (the owner, 2026-11-12).
@Suite("Pull requests and issues named as #123")
struct ForgeReferencesTests {
    @Test func `only a number that starts a word counts, once each, in order, at most five`() {
        #expect(ForgeReferences.numbers(in: "fix #12, see #7 and #12; not a#3, #t4, #4x or #") == [12, 7])
        #expect(ForgeReferences.numbers(in: "#1 #2 #3 #4 #5 #6") == [1, 2, 3, 4, 5])
        #expect(ForgeReferences.numbers(in: "see #9" + "\n\n--- task t1 ---\n#8") == [9], "only the typed line")
    }

    @Test func `the origin remote names the repository, in its https and ssh forms`() {
        let expected = ForgeReferences.Repository(owner: "g-cqd", name: "ask")
        #expect(ForgeReferences.repository(fromRemote: "https://github.com/g-cqd/ask.git") == expected)
        #expect(ForgeReferences.repository(fromRemote: "git@github.com:g-cqd/ask.git\n") == expected)
        #expect(ForgeReferences.repository(fromRemote: "ssh://git@github.com/g-cqd/ask") == expected)
        #expect(ForgeReferences.repository(fromRemote: "https://gitlab.com/g-cqd/ask.git") == nil)
        #expect(ForgeReferences.repository(fromRemote: "https://github.com/../x") == nil)
    }

    @Test func `a pull request and an issue read as their state, title and body`() throws {
        let pull =
            #"{"number":12,"title":"Fix it","state":"closed","html_url":"https://github.com/o/r/pull/12","body":"Body\ntext","user":{"login":"gigi"},"pull_request":{"merged_at":"2026-11-01T00:00:00Z"}}"#
        let item = try #require(ForgeReferences.item(from: Array(pull.utf8)))
        #expect(
            item
                == .init(
                    number: 12,
                    title: "Fix it",
                    state: "merged",
                    kind: "pull request",
                    author: "gigi",
                    url: "https://github.com/o/r/pull/12",
                    body: "Body\ntext"
                )
        )
        let issue = #"{"number":7,"title":"Broken","state":"open","html_url":"u","body":null,"user":{"login":"x"}}"#
        #expect(ForgeReferences.item(from: Array(issue.utf8))?.kind == "issue")
        #expect(ForgeReferences.item(from: Array("{}".utf8)) == nil)
    }

    @Test func `the attachment follows the message, and the screen still shows the typed line`() {
        let item = ForgeReferences.Item(
            number: 7,
            title: "Broken",
            state: "open",
            kind: "issue",
            author: "x",
            url: "u",
            body: String(repeating: "b", count: 5_000)
        )
        let sent = ForgeReferences.attach("look at #7", items: [item])
        #expect(sent.hasPrefix("look at #7\n\n--- github #7 ---\nissue #7 (open) by x: Broken\nu\n\n"))
        #expect(sent.hasSuffix("[cut at 4000 characters]\n--- end of #7 ---"))
        #expect(SkillInvocation.shown(sent) == "look at #7")
        #expect(ForgeReferences.attach("plain", items: []) == "plain")
    }

    @Test func `a list of open pull requests and issues reads as items, in its order`() {
        let list =
            #"[{"number":3,"title":"A","state":"open","html_url":"u3","user":{"login":"x"},"pull_request":{}},{"number":2,"title":"B","state":"open","html_url":"u2","user":{"login":"y"}},{"nope":1}]"#
        let items = ForgeReferences.items(fromList: Array(list.utf8))
        #expect(items.map(\.number) == [3, 2])
        #expect(items.map(\.kind) == ["pull request", "issue"])
        #expect(ForgeReferences.items(fromList: Array("{}".utf8)).isEmpty)
    }
}
