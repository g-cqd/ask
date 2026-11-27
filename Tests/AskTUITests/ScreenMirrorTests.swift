internal import Darwin
internal import Foundation
internal import TerminalKitIO
internal import Testing

@testable import AskTUI

/// A gateway viewer's terminal mirrors the running screen (ADR-0170), each on a pseudo-terminal as a real one would be: the mirror is
/// entered and drawn at its own size, what is typed there reaches the screen, a resize redraws it, and when the screen closes the
/// mirror's terminal is left as it was found.
@Suite("A viewer's terminal mirrors the running screen", .serialized)
struct ScreenMirrorTests {
    /// A pseudo-terminal pair: the screen side, and the side a person (or the test) types into and reads from.
    private struct PTY {
        let primary: Int32
        let replica: Int32

        init(columns: UInt16, rows: UInt16) throws {
            var primary: Int32 = -1
            var replica: Int32 = -1
            var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
            guard unsafe openpty(&primary, &replica, nil, nil, &size) == 0 else { throw POSIXError(.ENOTTY) }
            self.primary = primary
            self.replica = replica
        }

        func type(_ text: String) {
            _ = Array(text.utf8).withUnsafeBytes { unsafe write(primary, $0.baseAddress, $0.count) }
        }

        func resize(columns: UInt16, rows: UInt16) {
            var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
            _ = unsafe ioctl(primary, UInt(TIOCSWINSZ), &size)
        }

        /// What the screen side wrote, read until `until` is in it or `seconds` pass.
        func read(until needle: String, seconds: Double = 15) -> String {
            var seen: [UInt8] = []
            let deadline = Date().addingTimeInterval(seconds)
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while Date() < deadline {
                var descriptor = pollfd(fd: primary, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptor, 1, 50) > 0 else { continue }
                let count = buffer.withUnsafeMutableBytes { unsafe Darwin.read(primary, $0.baseAddress, $0.count) }
                guard count > 0 else { break }
                seen += buffer[..<count]
                if String(decoding: seen, as: UTF8.self).contains(needle) { break }
            }
            return String(decoding: seen, as: UTF8.self)
        }

        func close() {
            Darwin.close(primary)
            Darwin.close(replica)
        }
    }

    private final class Quiet: Conversation {
        func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
            Task { update(.runEnded) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a viewer's terminal is drawn, types into the screen, resizes, and is left whole`() async throws {
        let screen = try PTY(columns: 80, rows: 24)
        let viewer = try PTY(columns: 60, rows: 20)
        defer {
            Darwin.close(screen.replica)
            viewer.close()
        }
        let (resizes, _) = AsyncStream<Void>.makeStream()
        // A place of its own: other tests run screens in this process at the same time.
        let mirrors = ScreenMirrors()
        let running = Task {
            try await runInteractiveScreen(
                on: POSIXTerminalConnection(fileDescriptor: screen.replica),
                conversation: Quiet(),
                label: "mirror-test",
                resizes: resizes,
                mirrors: mirrors
            )
        }
        // The screen registers for mirrors before its first frame, so once that frame is drawn it can be mirrored.
        _ = screen.read(until: "mirror-test")
        #expect(mirrors.isRunning)

        let id = try #require(mirrors.attach(POSIXTerminalConnection(fileDescriptor: viewer.replica)))
        let entered = viewer.read(until: "mirror-test")
        #expect(entered.contains("\u{1B}[?1049h"), "the mirror enters the alternate screen")
        #expect(entered.contains("mirror-test"), "and is drawn from the screen's state")
        #expect(!entered.contains("\u{1B}[?1000h"), "the pointer is not asked for")

        viewer.type("hello from afar")
        let mirrored = viewer.read(until: "afar")
        let drawn = screen.read(until: "afar")
        #expect(
            drawn.contains("afar"),
            "what the viewer types reaches the screen: \(drawn.suffix(300).debugDescription) | viewer: \(mirrored.suffix(300).debugDescription)"
        )

        viewer.resize(columns: 100, rows: 30)
        mirrors.resized(id)
        #expect(viewer.read(until: "mirror-test").contains("mirror-test"), "a resize redraws the mirror")

        // The screen's terminal hangs up: its input ends and the screen closes, as when its window is closed.
        Darwin.close(screen.primary)
        _ = try await running.value
        #expect(
            viewer.read(until: "\u{1B}[?1049l").contains("\u{1B}[?1049l"),
            "the mirror is left when the screen closes"
        )
        #expect(!mirrors.isRunning)
    }

    @Test func `no screen running, nothing attaches`() throws {
        let viewer = try PTY(columns: 60, rows: 20)
        defer { viewer.close() }
        #expect(ScreenMirrors().attach(POSIXTerminalConnection(fileDescriptor: viewer.replica)) == nil)
    }
}
