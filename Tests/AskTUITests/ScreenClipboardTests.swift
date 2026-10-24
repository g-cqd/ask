internal import Foundation
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// The clipboard plan is carried out: the escape sequence to the terminal, the pasteboard where the terminal cannot be trusted.
@Suite("A copy reaches the clipboard the terminal can take it to")
struct ScreenClipboardTests {
    @Test func `a terminal that takes OSC 52 gets the escape sequence and the pasteboard is left alone`() {
        let connection = MockTerminalConnection()
        let recorder = ClipboardRecorder()
        var clipboard = ScreenClipboard(
            connection: connection, environment: ["TERM_PROGRAM": "ghostty"], pasteboard: recorder.pasteboard)
        _ = clipboard.copy("hello") { _, _ in }
        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(output.contains("\u{1B}]52;c;\(Data("hello".utf8).base64EncodedString())"))
        #expect(recorder.texts.isEmpty)
    }

    @Test func `Terminal dot app, which ignores OSC 52, gets the pasteboard`() async {
        let connection = MockTerminalConnection()
        let recorder = ClipboardRecorder()
        var clipboard = ScreenClipboard(
            connection: connection, environment: ["TERM_PROGRAM": "Apple_Terminal"], pasteboard: recorder.pasteboard)
        _ = await recorder.copy(&clipboard, "hello")
        #expect(connection.writtenOutput.isEmpty)
        #expect(recorder.texts == ["hello"])
    }

    @Test func `over ssh the local pasteboard is never used, whatever the terminal`() {
        let connection = MockTerminalConnection()
        let recorder = ClipboardRecorder()
        var clipboard = ScreenClipboard(
            connection: connection, environment: ["TERM_PROGRAM": "Apple_Terminal", "SSH_TTY": "/dev/ttys001"],
            pasteboard: recorder.pasteboard)
        _ = clipboard.copy("hello") { _, _ in }
        #expect(recorder.texts.isEmpty)
    }
}
