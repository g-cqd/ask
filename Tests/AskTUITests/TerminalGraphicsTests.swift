import Testing

@testable import AskTUI

/// Whether pictures are drawn as pixels (roadmap 0208): only in a terminal that says so, asked once with kitty's graphics query, and
/// asked only where the environment says the terminal may be kitty, Ghostty or WezTerm (the owner's choice, 2026-11-06), never through
/// tmux or ssh. A terminal that does not know the protocol may print the query as text, so it is not asked at all.
@Suite("The terminal is asked whether it draws kitty graphics, and its answer read")
struct TerminalGraphicsTests {
    @Test func `the query asks for one pixel, by ask's own id, and keeps nothing`() {
        let query = String(decoding: TerminalGraphics.query(), as: UTF8.self)
        #expect(query.hasPrefix("\u{1B}_G") && query.hasSuffix("\u{1B}\\"), "\(query)")
        #expect(
            query.contains("a=q") && query.contains("i=\(TerminalGraphics.queryID)") && query.contains("s=1")
                && query.contains("v=1")
        )
    }

    @Test func `the answer is read: OK draws, anything else does not, another id is not ours`() {
        let id = TerminalGraphics.queryID
        #expect(TerminalGraphics.answer(to: Array("\u{1B}_Gi=\(id);OK\u{1B}\\".utf8)) == .supported)
        #expect(TerminalGraphics.answer(to: Array("\u{1B}_Gi=\(id);ENOTSUPPORTED:no\u{1B}\\".utf8)) == .unsupported)
        #expect(TerminalGraphics.answer(to: Array("\u{1B}_Gi=7;OK\u{1B}\\".utf8)) == nil)
        #expect(TerminalGraphics.answer(to: Array("\u{1B}]11;rgb:0000/0000/0000\u{1B}\\".utf8)) == nil)
    }

    @Test func `asked only in kitty, Ghostty or WezTerm, and not through tmux or ssh`() {
        #expect(TerminalGraphics.mayDraw(environment: ["TERM": "xterm-kitty"]))
        #expect(TerminalGraphics.mayDraw(environment: ["TERM": "xterm-ghostty", "TERM_PROGRAM": "ghostty"]))
        #expect(TerminalGraphics.mayDraw(environment: ["TERM_PROGRAM": "WezTerm", "TERM": "xterm-256color"]))
        #expect(!TerminalGraphics.mayDraw(environment: ["TERM_PROGRAM": "Apple_Terminal", "TERM": "xterm-256color"]))
        #expect(!TerminalGraphics.mayDraw(environment: ["TERM": "xterm-kitty", "TMUX": "/tmp/tmux-501/default,1,0"]))
        #expect(!TerminalGraphics.mayDraw(environment: ["TERM": "xterm-kitty", "SSH_TTY": "/dev/ttys004"]))
    }
}
