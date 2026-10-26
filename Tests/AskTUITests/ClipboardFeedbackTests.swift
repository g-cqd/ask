internal import TerminalKitIO
internal import Testing

@testable import AskTUI

@Suite("Clipboard feedback says what is known: sent to the terminal, and what the host command did")
struct ClipboardFeedbackTests {
    @Test func `a terminal write is reported as sent, not acknowledged`() {
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "ghostty"],
            pasteboard: ClipboardRecorder().pasteboard)
        #expect(clipboard.copy("hello") { _, _ in } == "Copy sent to terminal")
    }

    @Test func `a host copy is pending until the command has exited, then copied`() async {
        let recorder = ClipboardRecorder()
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "Apple_Terminal"],
            pasteboard: recorder.pasteboard)
        let (initial, final) = await recorder.copy(&clipboard, "hello")
        #expect(initial == "Host copy pending")
        #expect(final?.notice == "Copied to host clipboard" && final?.failed == false)
    }

    @Test func `a host command that failed is reported as failed, with why`() async {
        let recorder = ClipboardRecorder(answering: .failed("pbcopy exited with status 1"))
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "Apple_Terminal"],
            pasteboard: recorder.pasteboard)
        let (_, final) = await recorder.copy(&clipboard, "hello")
        #expect(final?.notice == "Host copy failed: pbcopy exited with status 1" && final?.failed == true)
    }

    @Test func `both routes are reported, the terminal's as sent and the host's as it ended`() async {
        let recorder = ClipboardRecorder()
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "mystery"],
            pasteboard: recorder.pasteboard)
        let (initial, final) = await recorder.copy(&clipboard, "hello")
        #expect(initial == "Copy sent to terminal; host copy pending")
        #expect(final?.notice == "Copy sent to terminal; copied to host clipboard")
        let failing = ClipboardRecorder(answering: .failed("pbcopy could not start"))
        var other = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "mystery"],
            pasteboard: failing.pasteboard)
        #expect(
            await failing.copy(&other, "x").final?.notice
                == "Copy sent to terminal; host copy failed: pbcopy could not start")
    }

    @Test func `a terminal write that failed is not hidden by a host copy that worked`() async {
        let recorder = ClipboardRecorder()
        var clipboard = ScreenClipboard(
            connection: BrokenWrite(), environment: ["TERM_PROGRAM": "mystery"], pasteboard: recorder.pasteboard)
        let (initial, final) = await recorder.copy(&clipboard, "hello")
        #expect(initial.hasPrefix("Terminal copy failed:") && initial.hasSuffix("; host copy pending"))
        #expect(final?.notice.hasPrefix("Terminal copy failed:") == true)
        #expect(final?.notice.hasSuffix("; copied to host clipboard") == true)
    }

    @Test func `an unavailable remote clipboard is explained`() {
        var clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": "Apple_Terminal", "SSH_TTY": "remote"],
            pasteboard: ClipboardRecorder().pasteboard)
        #expect(clipboard.copy("hello") { _, _ in } == "Copy unavailable on this connection")
    }

    @Test func `a terminal write failure is not silently reported as sent`() {
        var clipboard = ScreenClipboard(
            connection: BrokenWrite(), environment: ["TERM_PROGRAM": "ghostty"],
            pasteboard: ClipboardRecorder().pasteboard)
        #expect(clipboard.copy("hello") { _, _ in }.hasPrefix("Copy failed:"))
    }

    @Test func `selection instructions and copy feedback are visible in the status line`() {
        var rig = PointerRig(
            columns: 100,
            options: ScreenOptions(copyOnSelect: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            lines: ["alpha beta"])
        rig.drag(from: (9, 0), to: (9, 4))
        #expect(rig.text(row: 11).contains("ctrl+c copy · esc clear"))
        rig.controller.state.clipboardNotice = "Copy sent to terminal"
        rig.draw()
        #expect(!rig.text(row: 11).contains("Copy sent to terminal"), "a copy that worked says nothing")
        rig.controller.state.clipboardNotice = "Terminal copy failed: broken pipe"
        rig.draw()
        #expect(rig.text(row: 11).contains("Terminal copy failed"), "a copy that went wrong says so")
    }

    @Test(arguments: [("ghostty", "Shift"), ("WezTerm", "Shift"), ("Apple_Terminal", "fn")])
    func `the native selection hint names the measured bypass key`(program: String, key: String) {
        let clipboard = ScreenClipboard(
            connection: MockTerminalConnection(), environment: ["TERM_PROGRAM": program],
            pasteboard: ClipboardRecorder().pasteboard)
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
