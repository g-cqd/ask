internal import TerminalKitIO
internal import Testing

@testable import AskTUI

@Suite("Clipboard feedback reports requests and failures without claiming acknowledgement")
struct ClipboardFeedbackTests {
    @Test func `a terminal write is reported as sent, not acknowledged`() {
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "ghostty"], pasteboard: { _ in })
        #expect(clipboard.copy("hello") == "Copy sent to terminal")
    }

    @Test func `host clipboard work is reported as queued`() {
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "Apple_Terminal"], pasteboard: { _ in })
        #expect(clipboard.copy("hello") == "Host copy queued")
    }

    @Test func `an unavailable remote clipboard is explained`() {
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "Apple_Terminal", "SSH_TTY": "remote"],
            pasteboard: { _ in })
        #expect(clipboard.copy("hello") == "Copy unavailable on this connection")
    }

    @Test func `a terminal write failure is not silently reported as sent`() {
        var clipboard = ScreenClipboard(
            connection: BrokenWrite(), environment: ["TERM_PROGRAM": "ghostty"], pasteboard: { _ in })
        #expect(clipboard.copy("hello").hasPrefix("Copy failed:"))
    }

    @Test func `selection instructions and copy feedback are visible in the status line`() {
        var rig = PointerRig(columns: 100, options: ScreenOptions(copyOnSelect: false), lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        #expect(rig.text(row: 10).contains("ctrl+c copy · esc clear"))
        rig.controller.state.clipboardNotice = "Copy sent to terminal"
        rig.draw()
        #expect(rig.text(row: 10).contains("Copy sent to terminal"))
    }

    @Test(arguments: [("ghostty", "Shift"), ("WezTerm", "Shift"), ("Apple_Terminal", "fn")])
    func `the native selection hint names the measured bypass key`(program: String, key: String) {
        let clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": program], pasteboard: { _ in })
        #expect(clipboard.nativeSelectionHint == "\(key): native selection")
    }

    private struct BrokenWrite: TerminalConnection {
        func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
        func write(_ bytes: [UInt8]) throws(TerminalError) { throw .connectionClosed }
        func enterRawMode() throws(TerminalError) {}
        func restoreMode() throws(TerminalError) {}
        func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 80, rows: 24) }
    }
}
