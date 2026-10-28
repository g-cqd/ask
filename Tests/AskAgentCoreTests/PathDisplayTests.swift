import Foundation
import Testing

@testable import AskAgentCore

@Suite("Path display formats tilde paths, clickable terminal links and paste-safe shell arguments")
struct PathDisplayTests {
    private let home = "/Users/testuser"

    @Test func `tilde replaces home prefix with tilde`() {
        #expect(PathDisplay.tilde("/Users/testuser", home: home) == "~")
        #expect(PathDisplay.tilde("/Users/testuser/Developer/project", home: home) == "~/Developer/project")
        #expect(
            PathDisplay.tilde("/Users/testuser/.local/state/ask/sessions/s1.jsonl", home: home)
                == "~/.local/state/ask/sessions/s1.jsonl")
        #expect(PathDisplay.tilde("/var/folders/temp", home: home) == "/var/folders/temp")
        #expect(PathDisplay.tilde("/Users/other/file", home: home) == "/Users/other/file")
    }

    @Test func `terminal link wraps path in OSC 8 sequence with file URI and display label`() {
        let link = PathDisplay.link(to: "/Users/testuser/my file.txt", display: "~/my file.txt")
        #expect(link.hasPrefix("\u{1B}]8;;file:///Users/testuser/my%20file.txt\u{1B}\\"))
        #expect(link.contains("~/my file.txt"))
        #expect(link.hasSuffix("\u{1B}]8;;\u{1B}\\"))
    }

    @Test func `shell argument leaves plain words, flags and tilde paths unquoted`() {
        #expect(PathDisplay.shellArgument("ask", home: home) == "ask")
        #expect(PathDisplay.shellArgument("--resume", home: home) == "--resume")
        #expect(PathDisplay.shellArgument("--no-sandbox", home: home) == "--no-sandbox")
        #expect(PathDisplay.shellArgument("/Users/testuser/Developer/ask", home: home) == "~/Developer/ask")
        #expect(
            PathDisplay.shellArgument("/Users/testuser/.local/state/ask/sessions/s1.jsonl", home: home)
                == "~/.local/state/ask/sessions/s1.jsonl")
    }

    @Test func `shell argument escapes spaces and special characters while keeping leading tilde unquoted`() {
        let path = "/Users/testuser/Work Space/project's ask"
        let escaped = PathDisplay.shellArgument(path, home: home)
        #expect(escaped.hasPrefix("~/Work\\ Space/project\\'s\\ ask"))
        #expect(!escaped.hasPrefix("'~"))
    }

    @Test func `a control character in a path never reaches the terminal as one`() {
        let hostile = "/Users/testuser/x\u{1B}]52;c;AAAA\u{07}y\nz"
        #expect(PathDisplay.hasControl(hostile))
        #expect(PathDisplay.hasControl("a\u{85}b"))
        #expect(PathDisplay.hasControl("a\u{7F}b"))
        #expect(!PathDisplay.hasControl("/Users/testuser/Work Space/é"))
        let link = PathDisplay.link(to: hostile)
        #expect(!link.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F })
        #expect(PathDisplay.sanitized("a\u{1B}b") == "a\u{FFFD}b")
        let labelled = PathDisplay.link(to: "/tmp/ok", display: "bad\u{07}label")
        #expect(!labelled.contains("\u{07}") && !labelled.contains("\u{1B}"))
    }
}
