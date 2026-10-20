internal import Foundation
internal import Synchronization
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// The clipboard plan is carried out: the escape sequence to the terminal, the pasteboard where the terminal cannot be trusted.
@Suite("A copy reaches the clipboard the terminal can take it to")
struct ScreenClipboardTests {
    // SAFETY: every access goes through the mutex, so the class has no unsynchronised state.
    private final class Pasteboard: @unchecked Sendable {
        private let copied = Mutex<[String]>([])
        var texts: [String] { copied.withLock { $0 } }
        func put(_ text: String) { copied.withLock { $0.append(text) } }
    }

    @Test func `a terminal that takes OSC 52 gets the escape sequence and the pasteboard is left alone`() {
        let connection = MockTerminalConnection()
        let pasteboard = Pasteboard()
        var clipboard = ScreenClipboard(
            connection: connection, environment: ["TERM_PROGRAM": "ghostty"], pasteboard: pasteboard.put)
        clipboard.copy("hello")
        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(output.contains("\u{1B}]52;c;\(Data("hello".utf8).base64EncodedString())"))
        #expect(pasteboard.texts.isEmpty)
    }

    @Test func `Terminal dot app, which ignores OSC 52, gets the pasteboard`() {
        let connection = MockTerminalConnection()
        let pasteboard = Pasteboard()
        var clipboard = ScreenClipboard(
            connection: connection, environment: ["TERM_PROGRAM": "Apple_Terminal"], pasteboard: pasteboard.put)
        clipboard.copy("hello")
        #expect(connection.writtenOutput.isEmpty)
        #expect(pasteboard.texts == ["hello"])
    }

    @Test func `over ssh the local pasteboard is never used, whatever the terminal`() {
        let connection = MockTerminalConnection()
        let pasteboard = Pasteboard()
        var clipboard = ScreenClipboard(
            connection: connection, environment: ["TERM_PROGRAM": "Apple_Terminal", "SSH_TTY": "/dev/ttys001"],
            pasteboard: pasteboard.put)
        clipboard.copy("hello")
        #expect(pasteboard.texts.isEmpty)
    }
}
