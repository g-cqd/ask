internal import AskGateway
internal import AskTUI
internal import Darwin
internal import Foundation

/// One viewer of this process's screen (ADR-0170), on a connection from the node: an `attach` naming this session and a size, then a
/// pseudo-terminal of that size attached to the screen as a mirror; what the screen writes to it goes back as `output`, `input` goes
/// to it as typed, and `resize` changes its size. It ends when either side does.
enum ViewerConnection {
    /// The most output bytes in one frame: the length is 2 bytes, less the kind byte.
    static let largestOutput = Int(UInt16.max) - 1

    /// Serves one viewer until it leaves or the screen closes.
    /// - Parameters:
    ///   - stream: the connection from the node.
    ///   - session: the id an `attach` must name.
    ///   - audit: records the viewer attaching and leaving.
    static func serve(_ stream: any ByteStream, session: String, audit: @Sendable (String, String) -> Void) async {
        var framing = NoiseFraming()
        var pending: [[UInt8]] = []
        guard let first = await next(stream, &framing, &pending),
            case .attach(let size, let named) = first
        else {
            await refuse(stream, "the first message must attach to a session")
            return
        }
        guard named == session else {
            await refuse(stream, "this process holds another session")
            return
        }
        guard let terminal = try? PseudoTerminal(columns: size.columns, rows: size.rows) else {
            await refuse(stream, "no pseudo-terminal could be made")
            return
        }
        guard let id = ScreenViewers.attach(replica: terminal.replica) else {
            Darwin.close(terminal.primary)
            await refuse(stream, "no screen is running in this session")
            return
        }
        audit("attached", "\(size.columns)x\(size.rows)")
        let output = Task { await relayOutput(from: terminal.primary, to: stream) }
        while let message = await next(stream, &framing, &pending) {
            switch message {
                case .input(let bytes): terminal.write(bytes)
                case .resize(let size):
                    terminal.resize(columns: size.columns, rows: size.rows)
                    ScreenViewers.resized(id)
                default: continue
            }
        }
        // The node let go: the screen lets the mirror go, which closes the replica, which ends the output relay.
        ScreenViewers.detach(id)
        await output.value
        audit("left", "")
        await stream.close()
    }

    /// The screen's output to the viewer, until the pseudo-terminal's replica is closed; then the viewer is told it ended.
    private static func relayOutput(from primary: Int32, to stream: any ByteStream) async {
        let chunks = DescriptorReader.pieces(of: primary, pieceSize: largestOutput) { Darwin.close(primary) }
        for await chunk in chunks {
            guard (try? await send(.output(chunk), on: stream)) != nil else { break }
        }
        try? await send(.ended("the session's screen let this viewer go"), on: stream)
    }

    private static func refuse(_ stream: any ByteStream, _ words: String) async {
        try? await send(.refused(words), on: stream)
        await stream.close()
    }

    private static func send(_ message: ChannelMessage, on stream: any ByteStream) async throws {
        try await stream.send(try NoiseFraming.frame(message.bytes))
    }

    /// The next channel message; nil when the stream ends or sends something that is not one.
    private static func next(_ stream: any ByteStream, _ framing: inout NoiseFraming, _ pending: inout [[UInt8]]) async
        -> ChannelMessage?
    {
        while pending.isEmpty {
            guard let piece = try? await stream.receive() else { return nil }
            pending += framing.read(piece)
        }
        return try? ChannelMessage(parsing: pending.removeFirst())
    }
}
