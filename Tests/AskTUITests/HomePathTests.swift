internal import Testing

@testable import AskTUI

/// The home folder is written `~` in what ask says, never in what was run or read (roadmap 0128).
@Suite("The home folder is shown as ~")
struct HomePathTests {
    private let home = "/Users/gigi"

    @Test func `a path under home starts with a tilde, and home alone is a tilde`() {
        #expect(HomePath.abbreviate("/Users/gigi/.config/ask/config.json", home: home) == "~/.config/ask/config.json")
        #expect(HomePath.abbreviate("/Users/gigi", home: home) == "~")
        #expect(HomePath.abbreviate("/Users/gigi/", home: home) == "~/")
    }

    @Test func `every path in a sentence is shortened, and only at a path boundary`() {
        let text =
            "wrote /Users/gigi/a.txt and (/Users/gigi/b) then \"/Users/gigi/c\"; not /Users/gigi2/x or /tmp/Users/gigi/y or /Users/gigix"
        #expect(
            HomePath.abbreviate(text, home: home)
                == "wrote ~/a.txt and (~/b) then \"~/c\"; not /Users/gigi2/x or /tmp/Users/gigi/y or /Users/gigix")
        #expect(HomePath.abbreviate("a=/Users/gigi/x:/Users/gigi/y", home: home) == "a=~/x:~/y")
    }

    @Test func `no home, a root home or an empty home changes nothing`() {
        for none: String? in [nil, "", "/"] {
            #expect(HomePath.abbreviate("/Users/gigi/a /x", home: none) == "/Users/gigi/a /x")
        }
        #expect(
            HomePath.abbreviate("/Users/gigi/a", home: "/Users/gigi/") == "~/a", "a trailing slash on home is ignored")
    }

    private func screen(_ updates: [ConversationUpdate]) -> ScreenController {
        var options = ScreenOptions()
        options.home = home
        options.verbose = true
        var controller = ScreenController(label: "m", options: options)
        for update in updates { controller.handle(update) }
        return controller
    }

    @Test func `ask's notices, details and questions show ~`() {
        var controller = screen([
            .notice("Configuration read from /Users/gigi/.config/ask/config.json", isError: false),
            .detail("session /Users/gigi/s.jsonl")
        ])
        #expect(
            controller.state.transcript.items == [
                .notice("Configuration read from ~/.config/ask/config.json", isError: false),
                .notice("session ~/s.jsonl", isError: false)
            ])
        controller.handle(.askApproval(id: 1, question: "Write /Users/gigi/x?"))
        #expect(controller.state.pendingApproval?.question == "Write ~/x?")
    }

    @Test func `a tool's path in its header shows ~, but a command, its input and the output stay as they were`() {
        let controller = screen([
            .toolStarted(
                name: "read", summary: "/Users/gigi/a.swift", id: "r", fullInput: "{\"path\":\"/Users/gigi/a.swift\"}"),
            .toolFinished(.succeeded, output: "let home = \"/Users/gigi\"", id: "r"),
            .toolStarted(
                name: "shell", summary: "", id: "c", fullInput: "ls /Users/gigi/src", command: ToolCommand()),
            .toolFinished(.succeeded, output: "/Users/gigi/src/a", id: "c")
        ])
        let items = controller.state.transcript.items
        guard case .tool(_, let summary, _, let output, let input) = items[0] else {
            Issue.record("no tool")
            return
        }
        #expect(
            summary == "~/a.swift" && output == "let home = \"/Users/gigi\""
                && input == "{\"path\":\"/Users/gigi/a.swift\"}")
        guard case .tool(_, _, _, let shellOutput, let command) = items[1] else {
            Issue.record("no shell")
            return
        }
        #expect(command == "ls /Users/gigi/src" && shellOutput == "/Users/gigi/src/a")
        #expect(controller.state.transcript.contentText(at: 1).contains("ls /Users/gigi/src"))
    }

    @Test func `the user's own words are never changed`() {
        let controller = screen([.userPrompt("open /Users/gigi/a"), .assistantText("see /Users/gigi/a")])
        #expect(controller.state.transcript.items == [.user("open /Users/gigi/a"), .assistant("see /Users/gigi/a")])
    }
}
