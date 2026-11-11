internal import Dispatch
internal import Foundation
internal import Synchronization
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// The terminal tab's title (notes n49 and n60; the owner's answers of 2026-11-11): `ask · name`, `ask · folder` until the
/// conversation has a name, set with OSC 0 and given back on exit from the terminal's title stack.
@Suite("The tab is titled after the conversation")
struct TabTitleTests {
    @Test func `ask and the name, else ask and the folder`() {
        #expect(TabTitle.text(name: "login redirect", workspace: "/Users/me/src/shop") == "ask · login redirect")
        #expect(TabTitle.text(name: nil, workspace: "/Users/me/src/shop") == "ask · shop")
        #expect(TabTitle.text(name: "  ", workspace: "/Users/me/src/shop/") == "ask · shop")
        #expect(TabTitle.text(name: nil, workspace: nil) == "ask")
        #expect(TabTitle.text(name: nil, workspace: "/") == "ask")
    }

    @Test func `nothing in a name can end or change the sequence`() {
        let text = TabTitle.text(name: "a\u{1B}]0;evil\u{07}b\u{9C}c\nd", workspace: nil)
        #expect(text == "ask · a]0;evilbcd")
        #expect(TabTitle.text(name: String(repeating: "x", count: 200), workspace: nil).count == TabTitle.limit)
    }

    @Test func `the title is set with OSC 0, and the terminal's own is kept and given back`() {
        #expect(TabTitle.sequence("ask · shop") == Array("\u{1B}]0;ask · shop\u{1B}\\".utf8))
        #expect(TabTitle.save == Array("\u{1B}[22;0t".utf8))
        #expect(TabTitle.restore == Array("\u{1B}[23;0t".utf8))
    }

    @Test func `the screen takes the name from the conversation, and a cleared one has none`() {
        var options = ScreenOptions()
        options.workspace = "/src/shop"
        var controller = ScreenController(label: "m", options: options)
        #expect(controller.tabTitle == "ask · shop")
        controller.handle(.conversationName("login redirect"))
        #expect(controller.tabTitle == "ask · login redirect")
        controller.handle(.clearConversation)
        #expect(controller.tabTitle == "ask · shop")
        controller.handle(.batch([.clearConversation, .conversationName("old work")]))
        #expect(controller.tabTitle == "ask · old work", "a resumed session's name")
    }

    /// A terminal whose first write blocks until released.
    private final class Stuck: TerminalConnection {
        let inner = MockTerminalConnection()
        let release = DispatchSemaphore(value: 0)
        private let first = Atomic<Bool>(true)

        func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
            try inner.read(into: buffer)
        }
        func write(_ bytes: [UInt8]) throws(TerminalError) { try writeContiguous(ContiguousArray(bytes)) }
        func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
            if first.exchange(false, ordering: .acquiringAndReleasing) { release.wait() }
            try inner.writeContiguous(bytes)
        }
        func enterRawMode() throws(TerminalError) { try inner.enterRawMode() }
        func restoreMode() throws(TerminalError) { try inner.restoreMode() }
        func getSize() throws(TerminalError) -> TerminalSize { try inner.getSize() }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a title never waits for a stuck terminal, keeps its order, and the last is written before ask goes`() {
        let terminal = Stuck()
        let writer = TabTitleWriter(connection: terminal)
        writer.send(TabTitle.save)
        writer.send(TabTitle.sequence("ask · shop"))
        #expect(terminal.inner.writtenOutput.isEmpty, "sent, not written: the terminal is stuck, and send returned")
        terminal.release.signal()
        writer.finish(TabTitle.restore)
        #expect(terminal.inner.writtenOutput == TabTitle.save + TabTitle.sequence("ask · shop") + TabTitle.restore)
    }
}
