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
}
