import Testing

@testable import AskAgentCore

/// A clicked URI as an opener reads it (roadmap 0216): a file or folder by its decoded path, a web link by its host; mail and other
/// schemes are left to the system.
@Suite("A clicked link is read as a file, a folder or a web page")
struct ClickedLinkTests {
    @Test func `a file link is its decoded path, a folder when the disk says so`() throws {
        let file = try #require(ClickedLink(uri: "file:///a/My%20Notes/b.md", isDirectory: { _ in false }))
        #expect(file == ClickedLink(kind: .file, url: "file:///a/My%20Notes/b.md", path: "/a/My Notes/b.md"))
        let folder = try #require(ClickedLink(uri: "file:///a/b", isDirectory: { $0 == "/a/b" }))
        #expect(folder.kind == .folder && folder.path == "/a/b")
    }

    @Test func `a web link is read with its host`() throws {
        let web = try #require(ClickedLink(uri: "https://www.github.com/x?y=1", isDirectory: { _ in false }))
        #expect(web == ClickedLink(kind: .web, url: "https://www.github.com/x?y=1", host: "www.github.com"))
    }

    @Test func `mail, other schemes and nonsense are left to the system`() {
        for uri in ["mailto:a@b.org", "vscode://open", "javascript:alert(1)", "not a uri", "file://"] {
            #expect(ClickedLink(uri: uri, isDirectory: { _ in false }) == nil, "\(uri)")
        }
    }

    @Test func `a place after the address is its line and column, and no part of the address`() throws {
        let both = try #require(ClickedLink(uri: "file:///a/b.swift#L12C5", isDirectory: { _ in false }))
        #expect(both == ClickedLink(kind: .file, url: "file:///a/b.swift", path: "/a/b.swift", line: 12, column: 5))
        let line = try #require(ClickedLink(uri: "file:///a/b.swift#L7", isDirectory: { _ in false }))
        #expect(line.line == 7 && line.column == nil && line.url == "file:///a/b.swift")
        // Anything else after `#` is the page's own, and left alone.
        let web = try #require(ClickedLink(uri: "https://x.example/a#L12", isDirectory: { _ in false }))
        #expect(web.url == "https://x.example/a#L12" && web.line == nil)
        let odd = try #require(ClickedLink(uri: "file:///a/b.swift#section", isDirectory: { _ in false }))
        #expect(odd.line == nil && odd.path == "/a/b.swift")
        let filled = OpenerChoice.choose(
            for: both,
            in: OpenersSection(rules: [OpenerRule(command: ["code", "--goto", "{path}:{line}:{column}"])])
        )
        #expect(filled == .command(["code", "--goto", "/a/b.swift:12:5"], rule: 0))
    }
}
