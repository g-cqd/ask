internal import Testing

@testable import AskTUI

/// Web and email addresses are found as paths are (roadmap 0075), so any block's text can be clicked open.
@Suite("Web and email addresses become links")
struct ContentLinksTests {
    private func links(_ text: String) -> [(String, String)] {
        PathLinks.links(in: text, home: "/Users/x")
            .map { link in
                let characters = Array(text)
                return (String(characters[link.columns]), link.uri)
            }
    }

    @Test func `a web address, without the punctuation around it`() {
        #expect(links("see https://example.com/a?b=1.").map(\.1) == ["https://example.com/a?b=1"])
        #expect(links("(https://x.org/y)").map(\.0) == ["https://x.org/y"])
        #expect(links("<http://x.org>").map(\.1) == ["http://x.org"])
        #expect(links("https://en.wikipedia.org/wiki/A_(b)").map(\.1) == ["https://en.wikipedia.org/wiki/A_(b)"])
    }

    @Test func `an email address opens a new mail`() {
        #expect(links("mail me at a.b+c@example.co.uk, thanks").map(\.1) == ["mailto:a.b+c@example.co.uk"])
        #expect(links("mailto:x@y.org").map(\.1) == ["mailto:x@y.org"])
    }

    @Test func `look-alikes are left alone`() {
        #expect(links("git@github.com:org/repo.git").isEmpty)
        #expect(links("user@host and @mention and a@b").isEmpty)
        #expect(links("https://").isEmpty)
        #expect(links("https://exämple.com").isEmpty, "a URI the terminal could not take as it is")
    }

    @Test func `a path and a web address on one row are both found, in order`() {
        #expect(links("/tmp/a.txt from https://x.org/a").map(\.1) == ["file:///tmp/a.txt", "https://x.org/a"])
    }
}
