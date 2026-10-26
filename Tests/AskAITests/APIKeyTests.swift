internal import Testing

@testable import AskAI

/// A pasted key is trimmed and checked before it is stored: it must not split a header or fill a file.
@Suite("A pasted API key is trimmed and checked")
struct APIKeyTests {
    @Test func `whitespace around a key is dropped`() { #expect(APIKey.clean("  sk-abc\n") == "sk-abc") }

    @Test(arguments: ["", "   ", "sk abc", "sk\nabc", "sk-é", "sk\u{7}abc"])
    func `a key with a space, a control character or a non-ASCII one is refused`(raw: String) {
        #expect(APIKey.clean(raw) == nil)
    }

    @Test func `a key past the limit is refused, and one at it is kept`() {
        #expect(APIKey.clean(String(repeating: "a", count: APIKey.lengthLimit)) != nil)
        #expect(APIKey.clean(String(repeating: "a", count: APIKey.lengthLimit + 1)) == nil)
    }
}
