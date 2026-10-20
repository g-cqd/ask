import Testing

@testable import AskTUI

@Suite("The screen's options keep ADR-0046's defaults")
struct ScreenOptionsTests {
    @Test func `the defaults are the ones the owner chose`() {
        let options = ScreenOptions()
        #expect(options.mouse && options.copyOnSelect && options.foldTools && options.foldThinking)
        #expect(options.scrollLines == 3)
    }

    @Test func `a wheel step scrolls at least one line`() {
        #expect(ScreenOptions(scrollLines: 0).scrollLines == 1)
        #expect(ScreenOptions(scrollLines: -4).scrollLines == 1)
    }
}
