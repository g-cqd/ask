internal import AskGateway
internal import CryptoKit
internal import Darwin
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskSession

/// The node (ADR-0170) between the gateway and this computer's viewer sockets, with the gateway played by the test and each viewer
/// socket a real socket pair: it publishes the shared sessions sealed to the trusted controller, relays an attached channel both ways,
/// refuses an unknown session and an untrusted controller, and ends the channel when the session lets the viewer go.
@Suite("The node relays the gateway's channels to this computer's sessions")
struct NodeAgentTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey
    private let nodeKey = Key()
    private let controllerKey = Key()
    private let size = ChannelMessage.Size(columns: 100, rows: 30)!
    private static let session = ViewerEndpoint.Description(id: "7", folder: "/srv/p", label: "m", started: "s")

    /// What the gateway is, for the test: frames in, and frames the node sent out.
    private actor Gateway {
        nonisolated let toNode: AsyncStream<RelayFrame>.Continuation
        private let sink: AsyncStream<RelayFrame>.Continuation
        private var incoming: AsyncStream<RelayFrame>.Iterator
        private var outgoing: AsyncStream<RelayFrame>.Iterator

        init() {
            let (toNodeStream, toNode) = AsyncStream<RelayFrame>.makeStream()
            let (fromNode, sink) = AsyncStream<RelayFrame>.makeStream()
            self.toNode = toNode
            self.sink = sink
            incoming = toNodeStream.makeAsyncIterator()
            outgoing = fromNode.makeAsyncIterator()
        }

        func nodeSent(_ frame: RelayFrame) { sink.yield(frame) }

        func nodeReceives() async -> RelayFrame? {
            var iterator = incoming
            let next = await iterator.next(isolation: self)
            incoming = iterator
            return next
        }

        /// The next frame the node sent.
        func next() async -> RelayFrame? {
            var iterator = outgoing
            let next = await iterator.next(isolation: self)
            outgoing = iterator
            return next
        }
    }

    /// The viewer sockets the node dials, each a socket pair: the node gets one end, the test the other, as it is dialled.
    private actor Viewers {
        private let sink: AsyncStream<TCPStream>.Continuation
        private var dialled: AsyncStream<TCPStream>.Iterator

        init() {
            let (stream, sink) = AsyncStream<TCPStream>.makeStream()
            self.sink = sink
            dialled = stream.makeAsyncIterator()
        }

        func dial() -> TCPStream {
            var pair: [Int32] = [-1, -1]
            _ = socketpair(AF_UNIX, SOCK_STREAM, 0, &pair)
            sink.yield(TCPStream(descriptor: pair[1]))
            return TCPStream(descriptor: pair[0])
        }

        /// The far end of the next socket the node dials.
        func next() async -> TCPStream? {
            var iterator = dialled
            let next = await iterator.next(isolation: self)
            dialled = iterator
            return next
        }
    }

    private func start(
        trusting trusted: [Key],
        starter: @escaping @Sendable (ChannelMessage.Size, String) async -> Result<String, GatewayStartPolicy.Refusal> =
            { _, _ in
                .failure(.init(reason: "starting disabled in test"))
            }
    ) -> (Gateway, Viewers, Task<Void, Never>) {
        let gateway = Gateway()
        let viewers = Viewers()
        let keys = trusted.map(\.publicKey)
        let raw = Set(keys.map(\.rawRepresentation))
        let sessions = SessionsBox([Self.session])
        let agent = NodeAgent(
            world: NodeAgent.World(
                send: { await gateway.nodeSent($0) },
                receive: { await gateway.nodeReceives() },
                sessions: { sessions.list() },
                folders: { ["/srv/p"] },
                trusted: { keys },
                dial: { _ in await viewers.dial() },
                start: { size, folder in
                    let result = await starter(size, folder)
                    if case .success(let id) = result {
                        sessions.add(ViewerEndpoint.Description(id: id, folder: folder, label: "m", started: "s2"))
                    }
                    return result
                },
                audit: { _, _ in }
            ),
            key: nodeKey,
            trusts: { raw.contains($0.rawRepresentation) }
        )
        let (rescans, _) = AsyncStream<Void>.makeStream()
        return (gateway, viewers, Task { await agent.run(rescans: rescans) })
    }

    private final class SessionsBox: Sendable {
        private let items: Mutex<[ViewerEndpoint.Description]>
        init(_ initial: [ViewerEndpoint.Description]) { items = Mutex(initial) }
        func list() -> [ViewerEndpoint.Description] { items.withLock { $0 } }
        func add(_ item: ViewerEndpoint.Description) { items.withLock { $0.append(item) } }
    }

    /// Opens channel `channel` as `key`, and returns the controller's side once the node answered.
    private func open(_ gateway: Gateway, as key: Key, channel: UInt32 = 1) async throws -> (
        ControllerChannel, RelayFrame?
    ) {
        var (controller, first) = try ControllerChannel.open(controllerKey: key, nodeKey: nodeKey.publicKey)
        gateway.toNode.yield(try RelayFrame(kind: .open, channel: channel, body: first))
        let answer = await gateway.next()
        if answer?.kind == .data, let answer { try controller.finish(answer.body) }
        return (controller, answer)
    }

    private static func read(_ stream: TCPStream) async -> ChannelMessage? {
        var framing = NoiseFraming()
        while let piece = try? await stream.receive() {
            if let bytes = framing.read(piece).first { return try? ChannelMessage(parsing: bytes) }
        }
        return nil
    }

    @Test(.timeLimit(.minutes(1)))
    func `the sessions are published sealed, and an attached channel relays both ways`() async throws {
        let (gateway, viewers, running) = start(trusting: [controllerKey])
        #expect(await gateway.next() == GatewayNode.hello)
        let list = try #require(await gateway.next())
        let opened = String(decoding: try SealedList.open(list.body, with: controllerKey), as: UTF8.self)
        #expect(list.kind == .list && opened.contains(#""id":"7""#) && opened.contains("/srv/p"))

        var (controller, answer) = try await open(gateway, as: controllerKey)
        #expect(answer?.kind == .data && controller.isOpen)
        gateway.toNode.yield(
            try RelayFrame(kind: .data, channel: 1, body: try controller.send(.attach(size, session: "7")))
        )
        let viewer = try #require(await viewers.next())
        #expect(await Self.read(viewer) == .attach(size, session: "7"), "the viewer socket is asked to attach")

        try await viewer.send(try NoiseFraming.frame(ChannelMessage.output(Array("ask> ".utf8)).bytes))
        let output = try #require(await gateway.next())
        #expect(
            try controller.receive(output.body) == .output(Array("ask> ".utf8)),
            "the screen reaches the controller"
        )

        gateway.toNode.yield(
            try RelayFrame(kind: .data, channel: 1, body: try controller.send(.input(Array("y".utf8))))
        )
        #expect(await Self.read(viewer) == .input(Array("y".utf8)), "the controller's typing reaches the viewer socket")

        try await viewer.send(try NoiseFraming.frame(ChannelMessage.ended("closed").bytes))
        let ended = try #require(await gateway.next())
        #expect(try controller.receive(ended.body) == .ended("closed"))
        #expect(await gateway.next()?.kind == .close)
        gateway.toNode.finish()
        await running.value
    }

    @Test(.timeLimit(.minutes(1)))
    func `an unknown session, or an untrusted controller, is refused`() async throws {
        let (gateway, _, running) = start(trusting: [controllerKey])
        _ = await gateway.next()
        _ = await gateway.next()
        var (controller, _) = try await open(gateway, as: controllerKey)
        gateway.toNode.yield(
            try RelayFrame(kind: .data, channel: 1, body: try controller.send(.attach(size, session: "8")))
        )
        let refused = try #require(await gateway.next())
        guard case .refused = try controller.receive(refused.body) else {
            Issue.record("not refused")
            return
        }
        #expect(await gateway.next()?.kind == .close)

        let (_, closed) = try await open(gateway, as: Key(), channel: 3)
        #expect(
            closed?.kind == .close && closed?.body.first == 1,
            "a controller this computer does not trust is closed out"
        )
        gateway.toNode.finish()
        await running.value
    }

    @Test(.timeLimit(.minutes(1)))
    func `starting a session publishes the updated list and attaches, or refuses when disallowed`() async throws {
        let (gateway, viewers, running) = start(trusting: [controllerKey]) { _, folder in
            folder == "/srv/p" ? .success("99") : .failure(.init(reason: "outside gateway.folders"))
        }
        _ = await gateway.next()
        _ = await gateway.next()

        var (controller, _) = try await open(gateway, as: controllerKey, channel: 1)
        gateway.toNode.yield(
            try RelayFrame(kind: .data, channel: 1, body: try controller.send(.start(size, folder: "/srv/p")))
        )
        let updated = try #require(await gateway.next())
        #expect(updated.kind == .list)
        let opened = String(decoding: try SealedList.open(updated.body, with: controllerKey), as: UTF8.self)
        #expect(opened.contains(#""id":"99""#))
        let viewer = try #require(await viewers.next())
        #expect(await Self.read(viewer) == .attach(size, session: "99"))

        var (second, _) = try await open(gateway, as: controllerKey, channel: 3)
        gateway.toNode.yield(
            try RelayFrame(kind: .data, channel: 3, body: try second.send(.start(size, folder: "/etc")))
        )
        let refused = try #require(await gateway.next())
        guard case .refused(let words) = try second.receive(refused.body) else {
            Issue.record("expected refusal")
            return
        }
        #expect(words.contains("outside"))
        #expect(await gateway.next()?.kind == .close)
        await viewer.close()
        gateway.toNode.finish()
        await running.value
    }
}
