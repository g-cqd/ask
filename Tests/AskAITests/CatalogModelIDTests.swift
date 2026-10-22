internal import Testing

@testable import AskAI

/// Every model id in three real public lists (OpenRouter 468, Hugging Face's router 134, NVIDIA 81, probed 2026-10-20) has a `/` in
/// it, OpenRouter's free ones end in `:free`, and its 19 "latest" aliases start with `~`. A rule that refused them would have emptied every catalog (diary 55).
struct CatalogModelIDTests {
    @Test(arguments: [
        "gpt-6.1-sol", "minimax/minimax-m3.1-flash:free", "deepseek-ai/DeepSeek-V4.1-Flash-1017", "01-ai/yi-large",
        "~unbiased/pareto-latest", "~a", "a", String(repeating: "m", count: 128),
        "~" + String(repeating: "m", count: 127)
    ])
    func `an id the real lists use is accepted`(_ id: String) {
        #expect(CatalogModel.validID(id))
    }

    @Test(arguments: [
        "", " ", "a b", "/lead", ":lead", "~", "~~a", "~/a", "~-a", "a~b", "-lead", ".lead", "_lead", "a\nb", "a\tb",
        "a\"b", "a\\b",
        "a\u{7F}b",
        "é", "a\u{202E}b", String(repeating: "m", count: 129), "~" + String(repeating: "m", count: 128)
    ])
    func `an id that could split a header, a line or a JSON string is refused`(_ id: String) {
        #expect(!CatalogModel.validID(id))
    }

    @Test func `alias and connection names keep the narrow rule, so a name never gains a slash`() {
        #expect(!PlainToken.word("a/b", length: 1 ... 64, lowercase: false))
        #expect(!PlainToken.word("a:b", length: 1 ... 64, lowercase: false))
        #expect(PlainToken.word("a.b_c-d", length: 1 ... 64, lowercase: false))
    }
}
