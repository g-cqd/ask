internal import AskGateway
internal import Darwin
internal import Foundation
internal import Synchronization
internal import TerminalKitIO
internal import Testing

@testable import AskSession
@testable import AskTUI

/// The viewer endpoint (ADR-0170) in front of a running screen, through its real Unix socket: a node attaches with a size and
/// receives the screen, its input reaches the screen, a wrong session or a first message that is not an attach is refused, and the
/// socket and its description are owner-only and gone once it stops.
@Suite("A node attaches to this process's screen through the viewer endpoint", .serialized)
struct ViewerEndpointTests {
    private final class Quiet: Conversation {
        func start(_ prompt: String, update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never> {
            Task { update(.runEnded) }
        }
    }

    /// A connected client of the endpoint's socket.
    private static func connect(_ path: String) throws -> TCPStream {
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in path.utf8.enumerated() { raw[index] = byte }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        return TCPStream(descriptor: client)
    }

    private static func send(_ message: ChannelMessage, _ stream: TCPStream) async throws {
        try await stream.send(try NoiseFraming.frame(message.bytes))
    }

    /// Reads messages until one satisfies `done`, or the stream ends; what the screen drew, joined.
    private static func read(_ stream: TCPStream, until done: (String, ChannelMessage) -> Bool) async -> (
        String, ChannelMessage?
    ) {
        var framing = NoiseFraming()
        var drawn = ""
        while let piece = try? await stream.receive() {
            for bytes in framing.read(piece) {
                guard let message = try? ChannelMessage(parsing: bytes) else { continue }
                if case .output(let output) = message { drawn += String(decoding: output, as: UTF8.self) }
                if done(drawn, message) { return (drawn, message) }
            }
        }
        return (drawn, nil)
    }

    private func folder() -> String {
        // Short: a Unix socket's path is at most 103 bytes.
        "/tmp/askv-\(UUID().uuidString.prefix(8))"
    }

    @Test(.timeLimit(.minutes(1)))
    func `a node attaches, receives the screen, and types into it`() async throws {
        let size = try #require(ChannelMessage.Size(columns: 90, rows: 25))
        let directory = folder()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let audits = AuditLog()
        let endpoint = try ViewerEndpoint(
            in: directory,
            description: .init(
                id: "4242",
                folder: "/srv/project",
                label: "viewer-test",
                started: "2026-11-26T00:00:00Z"
            ),
            audit: { what, _ in audits.add(what) }
        )
        defer { endpoint.stop() }
        let permissions = try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
        let socketMode =
            try FileManager.default.attributesOfItem(atPath: endpoint.socketPath)[.posixPermissions] as? Int
        #expect(socketMode.map { $0 & 0o077 } == 0, "no one but the owner may connect")

        // A screen running in this process, on a pseudo-terminal so its input stays open.
        let terminal = try PseudoTerminal(columns: 80, rows: 24)
        let (resizes, _) = AsyncStream<Void>.makeStream()
        let running = Task {
            try await runInteractiveScreen(
                on: POSIXTerminalConnection(fileDescriptor: terminal.replica),
                conversation: Quiet(),
                label: "viewer-test",
                resizes: resizes
            )
        }
        // The screen registers for viewers before its first frame: once that frame is drawn, it can be viewed.
        _ = terminal.read { $0.contains("viewer-test") }
        #expect(ScreenViewers.isRunning)

        let node = try Self.connect(endpoint.socketPath)
        try await Self.send(.attach(size, session: "4242"), node)
        let (drawn, _) = await Self.read(node) { drawn, _ in drawn.contains("viewer-test") }
        #expect(drawn.contains("\u{1B}[?1049h") && drawn.contains("viewer-test"))

        try await Self.send(.input(Array("typed remotely".utf8)), node)
        // Frames are differences, so the typing arrives in pieces between cursor moves: its characters, in order, are what show.
        let (typed, _) = await Self.read(node) { drawn, _ in TerminalOutput.shows("typed remotely", in: drawn) }
        #expect(
            TerminalOutput.shows("typed remotely", in: typed),
            "the viewer's typing reaches the screen, which draws it for the viewer too"
        )

        await node.close()
        // The screen's terminal hangs up, and the screen closes.
        Darwin.close(terminal.primary)
        _ = try? await running.value
        #expect(audits.entries.first == "attached")
    }

    @Test func `a wrong session, or a first message that is not an attach, is refused`() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let endpoint = try ViewerEndpoint(
            in: directory,
            description: .init(id: "1", folder: "/srv", label: "l", started: "x"),
            audit: { _, _ in }
        )
        let size = try #require(ChannelMessage.Size(columns: 80, rows: 24))
        for first: ChannelMessage in [.attach(size, session: "2"), .input([0x61])] {
            let node = try Self.connect(endpoint.socketPath)
            try await Self.send(first, node)
            let (_, last) = await Self.read(node) { _, message in if case .refused = message { true } else { false } }
            guard case .refused = last else {
                Issue.record("not refused: \(String(describing: last))")
                return
            }
        }
        endpoint.stop()
        #expect(!FileManager.default.fileExists(atPath: endpoint.socketPath))
        #expect(!FileManager.default.fileExists(atPath: directory + "/1.json"))
    }

    /// What the endpoint audited, in order.
    private final class AuditLog: Sendable {
        private let lines = Mutex<[String]>([])
        func add(_ what: String) { lines.withLock { $0.append(what) } }
        var entries: [String] { lines.withLock { $0 } }
    }
}
