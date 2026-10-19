internal import Testing

@testable import AskAI

/// The shape an id, code or account name must have before it is put in a path, a header or a form: ASCII letters and
/// digits and a few named marks, within a length. A look-alike letter or a separator is how an id climbs out of the
/// place it is put.
@Suite("A plain token is ASCII letters, digits and the marks it names, of a bounded length")
struct PlainTokenTests {
    @Test func `letters, digits and the named marks within the length are plain`() {
        #expect(PlainToken.matches("aZ09_-.", length: 1 ... 10, extra: "_-."))
        #expect(PlainToken.matches("a", length: 1 ... 1, extra: ""))
    }

    @Test(arguments: ["", "a b", "a/b", "a\u{0}b", "a\nb", "é", "ａ", "a%2e", "a:b", "a;b"])
    func `anything else is not, including look-alike letters and separators`(value: String) {
        #expect(!PlainToken.matches(value, length: 1 ... 10, extra: "_-."), "\(value.debugDescription)")
    }

    @Test func `only the marks a caller names are allowed`() {
        #expect(!PlainToken.matches("a.b", length: 1 ... 10, extra: "_-"))
        #expect(PlainToken.matches("a.b", length: 1 ... 10, extra: "."))
    }

    @Test func `the length is counted in bytes and bounded on both sides`() {
        #expect(!PlainToken.matches("abcd", length: 1 ... 3, extra: ""))
        #expect(!PlainToken.matches("ab", length: 3 ... 5, extra: ""))
        #expect(PlainToken.matches("abc", length: 3 ... 3, extra: ""))
    }
}
