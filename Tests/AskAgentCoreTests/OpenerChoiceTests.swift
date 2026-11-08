import Testing

@testable import AskAgentCore

/// Which opener a clicked link gets (roadmap 0216, ADR-0148): the first rule whose every criterion holds, else the kind's app, else the
/// system's; a command's placeholders filled inside their own argument, and refused where a value would read as an option.
@Suite("A clicked link gets the first rule that matches it")
struct OpenerChoiceTests {
    private static let openers = OpenersSection(
        file: "Xcode",
        web: "Safari",
        rules: [
            OpenerRule(kind: .file, extensions: ["MD"], app: "Typora"),
            OpenerRule(pattern: "/work/.+\\.swift$", command: ["code", "--goto", "{path}:{line}:{column}"]),
            OpenerRule(host: "github.com", app: "Arc"),
            OpenerRule(kind: .folder, command: ["open", "-a", "Terminal", "{path}"])
        ]
    )

    private func file(_ path: String, line: Int? = nil) -> ClickedLink {
        ClickedLink(kind: .file, url: "file://" + path, path: path, line: line)
    }

    @Test func `the first matching rule wins, then the kind's app, then the system's`() {
        #expect(OpenerChoice.choose(for: file("/a/notes.md"), in: Self.openers) == .app("Typora"))
        #expect(OpenerChoice.choose(for: file("/a/b.swift"), in: Self.openers) == .app("Xcode"))
        let web = ClickedLink(kind: .web, url: "https://www.github.com/x", host: "www.github.com")
        #expect(OpenerChoice.choose(for: web, in: Self.openers) == .app("Arc"))
        let other = ClickedLink(kind: .web, url: "https://example.com", host: "example.com")
        #expect(OpenerChoice.choose(for: other, in: Self.openers) == .app("Safari"))
        #expect(OpenerChoice.choose(for: file("/a/b.swift"), in: OpenersSection()) == .system)
    }

    @Test func `a command's placeholders fill their own argument, a missing line or column as 1`() {
        #expect(
            OpenerChoice.choose(for: file("/work/x y.swift", line: 12), in: Self.openers)
                == .command(["code", "--goto", "/work/x y.swift:12:1"], rule: 1)
        )
        let folder = ClickedLink(kind: .folder, url: "file:///tmp/a", path: "/tmp/a")
        #expect(
            OpenerChoice.choose(for: folder, in: Self.openers)
                == .command(["open", "-a", "Terminal", "/tmp/a"], rule: 3)
        )
    }

    @Test func `a value that would read as an option is refused`() {
        let openers = OpenersSection(rules: [OpenerRule(kind: .file, command: ["tool", "{path}"])])
        guard case .refused = OpenerChoice.choose(for: file("-rf"), in: openers) else {
            Issue.record("a path starting with - must be refused")
            return
        }
        #expect(OpenerChoice.choose(for: file("/a/-b"), in: openers) == .command(["tool", "/a/-b"], rule: 0))
    }

    @Test func `a value holding a placeholder's name is not filled again`() {
        let openers = OpenersSection(rules: [OpenerRule(kind: .file, command: ["x", "{path} at {line}"])])
        #expect(
            OpenerChoice.choose(for: file("/a/{url}{line}.txt", line: 3), in: openers)
                == .command(["x", "/a/{url}{line}.txt at 3"], rule: 0)
        )
    }

    @Test func `a placeholder fills only itself, never splitting or quoting`() {
        let openers = OpenersSection(rules: [OpenerRule(kind: .web, command: ["fetch", "--url={url}"])])
        let web = ClickedLink(kind: .web, url: "https://a.com/x;rm -rf ~", host: "a.com")
        #expect(
            OpenerChoice.choose(for: web, in: openers) == .command(["fetch", "--url=https://a.com/x;rm -rf ~"], rule: 0)
        )
    }
}
