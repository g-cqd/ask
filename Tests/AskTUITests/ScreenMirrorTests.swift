internal import AskGateway
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
    private final class Quiet: Conversation {
        func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
            Task { update(.runEnded) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a viewer's terminal is drawn, types into the screen, resizes, and is left whole`() async throws {
        let screen = try PseudoTerminal(columns: 80, rows: 24)
        let viewer = try PseudoTerminal(columns: 60, rows: 20)
        defer {
            for descriptor in [screen.replica, viewer.primary, viewer.replica] { Darwin.close(descriptor) }
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
        _ = screen.read { $0.contains("mirror-test") }
        #expect(mirrors.isRunning)

        let id = try #require(mirrors.attach(POSIXTerminalConnection(fileDescriptor: viewer.replica)))
        let entered = viewer.read { $0.contains("mirror-test") }
        #expect(entered.contains("\u{1B}[?1049h"), "the mirror enters the alternate screen")
        #expect(entered.contains("mirror-test"), "and is drawn from the screen's state")
        #expect(!entered.contains("\u{1B}[?1000h"), "the pointer is not asked for")

        viewer.write(Array("hello from afar".utf8))
        // Frames are differences: the typing arrives in pieces between cursor moves, so its characters, in order, are what show.
        let drawn = screen.read { TerminalOutput.shows("hello from afar", in: $0) }
        #expect(TerminalOutput.shows("hello from afar", in: drawn), "what the viewer types reaches the screen")

        viewer.resize(columns: 100, rows: 30)
        mirrors.resized(id)
        #expect(viewer.read { $0.contains("mirror-test") }.contains("mirror-test"), "a resize redraws the mirror")

        // The screen's terminal hangs up: its input ends and the screen closes, as when its window is closed.
        Darwin.close(screen.primary)
        _ = try await running.value
        #expect(
            viewer.read { $0.contains("\u{1B}[?1049l") }.contains("\u{1B}[?1049l"),
            "the mirror is left when the screen closes"
        )
        #expect(!mirrors.isRunning)
    }

    @Test func `no screen running, nothing attaches`() throws {
        let viewer = try PseudoTerminal(columns: 60, rows: 20)
        defer { for descriptor in [viewer.primary, viewer.replica] { Darwin.close(descriptor) } }
        #expect(ScreenMirrors().attach(POSIXTerminalConnection(fileDescriptor: viewer.replica)) == nil)
    }
}
