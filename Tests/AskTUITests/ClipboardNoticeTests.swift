internal import Testing

@testable import AskTUI

/// What the status line says after a copy or a click: a copy that worked says nothing, and anything that did not happen as asked is
/// said, a clicked link not opened among them (found by `probe-openers.py`: link notices were never shown).
@Suite("The status line says what did not happen")
struct ClipboardNoticeTests {
    @Test func `a copy that worked says nothing, and a failed one is said`() {
        #expect(!ClipboardNotice.needsAttention("Copied 12 characters."))
        #expect(ClipboardNotice.needsAttention("Copy failed: the pasteboard is unavailable."))
    }

    @Test func `a link not opened, shown in the Finder, or not run is said`() {
        for notice in [
            "Not opened: only web, mail and file links open, and only files that are there.",
            "Shown in the Finder, not opened: it would run.", "Nothing opened https://x.example.",
            "Not run: /a/-b would be read as an option."
        ] {
            #expect(ClipboardNotice.needsAttention(notice), "\(notice)")
        }
    }
}
