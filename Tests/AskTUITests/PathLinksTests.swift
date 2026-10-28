internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

@Suite("Paths in tool rows become terminal hyperlinks (roadmap 0075)")
struct PathLinksTests {
    private func found(_ text: String) -> [String] {
        PathLinks.links(in: text, home: "/Users/me")
            .map { link in
                let characters = Array(text)
                return String(characters[link.columns])
            }
    }

    @Test func `an absolute path and a home path are linked, a location after it is not part of the link`() {
        #expect(found("  read /tmp/a.swift") == ["/tmp/a.swift"])
        #expect(found("error: /tmp/a.swift:12:5: boom") == ["/tmp/a.swift"])
        #expect(found("see ~/src/x.md.") == ["~/src/x.md"])
        #expect(found(#"cat "/tmp/a b""#) == ["/tmp/a"])
    }

    @Test func `urls, comments and relative paths are left alone`() {
        #expect(found("https://example.com/a/b").isEmpty)
        #expect(found("// comment /").isEmpty)
        #expect(found("Sources/ask/main.swift:3").isEmpty)
    }

    @Test func `the uri is percent-encoded and home is expanded`() {
        #expect(PathLinks.links(in: "~/a b/c", home: "/Users/me").first?.uri == "file:///Users/me/a")
        let encoded = PathLinks.uri("/opt/é", home: "/h")
        #expect(encoded == "file:///opt/%C3%A9", "\(String(describing: encoded))")
    }

    @Test func `a path holding a control character gets no link`() {
        #expect(PathLinks.uri("/tmp/a\u{1B}]8;;x", home: "/h") == nil)
        #expect(found("/tmp/a\u{1B}b").allSatisfy { !$0.contains("\u{1B}") })
    }

    @Test func `columns count wide characters`() {
        let links = PathLinks.links(in: "日本 /tmp/x", home: "/h")
        #expect(links.first?.columns == 5 ..< 11)
    }

    @Test func `a tool block's rows carry the links and the drawn spans open them`() {
        let item = Transcript.Item.tool(
            name: "read", summary: "/opt/a.swift", status: .succeeded, output: "/opt/b.swift:3: note")
        let lines = ScreenComposer.lines(for: item, columns: 80)
        #expect(lines.contains { !$0.links.isEmpty })
        let linked = lines.flatMap { ScreenComposer.spans(of: $0, highlight: nil) }.filter { $0.1.link != nil }
        #expect(linked.map(\.0).contains("/opt/b.swift"))
        let plain = ScreenComposer.lines(for: .assistant("/opt/b.swift"), columns: 80)
        #expect(plain.allSatisfy { $0.links.isEmpty })
    }
}
