internal import Testing

@testable import AskAI

/// A query or form body from name and value pairs, in the order given, with every reserved character escaped.
@Suite("A form query keeps the order, escapes what is reserved, and writes a space as asked")
struct FormEncodingTests {
    @Test func `pairs are joined in order and escaped`() {
        #expect(FormEncoding.query([("a", "1"), ("b", "x y"), ("c", "&=/?#")]) == "a=1&b=x+y&c=%26%3D%2F%3F%23")
    }

    @Test func `a space may be written as a percent escape for a parser that wants one`() {
        #expect(FormEncoding.query([("scope", "openid profile")], spaceAs: "%20") == "scope=openid%20profile")
    }

    @Test func `a literal plus is escaped whichever way a space is written`() {
        #expect(FormEncoding.query([("a", "1+1 2")]) == "a=1%2B1+2")
        #expect(FormEncoding.query([("a", "1+1 2")], spaceAs: "%20") == "a=1%2B1%202")
    }

    @Test func `no pairs is an empty string`() { #expect(FormEncoding.query([]) == "") }
}
