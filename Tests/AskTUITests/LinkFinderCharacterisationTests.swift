internal import Testing

@testable import AskTUI

/// What the path and address finders link, pinned before their byte prefilter (roadmap 0152): a line the prefilter skips must be one
/// they found nothing in. Tricky lines by hand, then seeded random lines over the characters the finders look at, with combining marks,
/// wide and emoji characters among them.
@Suite("The link finders link what they did before their prefilter")
struct LinkFinderCharacterisationTests {
    static let tricky = [
        "/usr/bin/swift", "see /tmp/a.txt:12:5.", "~/notes.md", "x//y", "// comment /not", "    /// Doc /path",
        "a /\u{301}b",
        "//\u{301}x", " /", "/", "~", "~/", "=/etc/hosts", "`/a/b`", "(/a)", "<~/b>", "\"/q\"", "'/q'", "[/q]",
        "\t/tab",
        "git@github.com:org/repo", "a/b@c.d", "mail me@example.com.", "x@y", "@inlinable func f()", "me@ex.co:",
        "é@ex.com",
        "https://example.com/a(b)c).", "http://x", "mailto:me@ex.com", "mailto:nope", "xhttps://a.b", "/https://a.b",
        "界 /tmp/界.txt 😀 ~/x", "e\u{301}@ex.com", "@\u{301}ex.com", "let label = \"row \\(1) of \\(count)\" // 3",
        "case .some(let x): return x", "url: https://a.b/c?d=e&f=g#h, then"
    ]

    /// The characters the finders look at, and some they skip past.
    static let alphabet: [String] = [
        "/", "/", "~", "@", "@", ":", ":", ".", " ", " ", "\t", "\"", "'", "(", ")", "[", "]", "<", ">", "=", "`", ",",
        "a", "b",
        "x", "1", "2", "_", "-", "+", "%", "h", "t", "p", "s", "m", "i", "l", "o", "http://", "https://", "mailto:",
        "é",
        "\u{301}", "界", "😀", "\u{7F}", "\u{1}"
    ]

    static func lines() -> [String] {
        var generator = SplitMix(seed: 0x5EED)
        var lines = tricky
        for _ in 0 ..< 20_000 {
            let count = Int(generator.next() % 24)
            lines.append((0 ..< count).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] }.joined())
        }
        return lines
    }

    static func digest() -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for line in lines() {
            let found = PathLinks.links(in: line, home: "/home/me").map { "\($0.columns)=\($0.uri)" }
                .joined(separator: ";")
            for byte in (found + "\n").utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100_0000_01B3
            }
        }
        return hash
    }

    @Test func `the links found in tricky and random lines keep their digest`() {
        #expect(Self.digest() == 2_935_008_911_567_666_217)
        let linked = Self.lines().filter { !PathLinks.links(in: $0, home: "/home/me").isEmpty }.count
        #expect(linked > 2_000, "the random lines must hold links for the digest to pin anything: \(linked)")
    }

    @Test func `the tricky lines that hold a link still link`() {
        #expect(PathLinks.links(in: "see /tmp/a.txt:12:5.", home: "/h").map(\.uri) == ["file:///tmp/a.txt"])
        #expect(PathLinks.links(in: "a /\u{301}b", home: "/h").isEmpty)
        #expect(PathLinks.links(in: "mail me@example.com.", home: "/h").map(\.uri) == ["mailto:me@example.com"])
    }
}
