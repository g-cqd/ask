internal import AemiJSON
internal import AskGateway
internal import CryptoKit
internal import Foundation

/// The node (ADR-0170), once linked to the gateway: it publishes this computer's shared sessions, sealed to the trusted controllers,
/// and relays each channel a controller opens to the viewer socket of the session it names. One link; it returns when the link ends.
actor NodeAgent {
    /// What the agent reaches the outside through.
    struct World: Sendable {
        /// Sends a frame to the gateway.
        let send: @Sendable (RelayFrame) async throws -> Void
        /// The next frame from the gateway; nil once the link ended.
        let receive: @Sendable () async throws -> RelayFrame?
        /// This computer's shared sessions now.
        let sessions: @Sendable () -> [ViewerEndpoint.Description]
        /// The controller keys trusted now.
        let trusted: @Sendable () -> [Curve25519.KeyAgreement.PublicKey]
        /// A connection to session `id`'s viewer socket; nil when it cannot be reached.
        let dial: @Sendable (String) async -> (any ByteStream)?
        /// Records a remote action: what, and the controller's fingerprint.
        let audit: @Sendable (String, String) -> Void
    }

    private let world: World
    private var node: GatewayNode
    private var viewers: [UInt32: any ByteStream] = [:]
    private var relays: [UInt32: Task<Void, Never>] = [:]
    private var published: [ViewerEndpoint.Description]?

    init(
        world: World,
        key: Curve25519.KeyAgreement.PrivateKey,
        trusts: @escaping @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
    ) {
        self.world = world
        node = GatewayNode(key: key, trusts: trusts)
    }

    /// Runs until the link ends: hello, the sessions, then every frame. `rescans` says when to look at the sessions again.
    func run(rescans: AsyncStream<Void>) async {
        guard (try? await world.send(GatewayNode.hello)) != nil else { return }
        await publish()
        let watching = Task { [weak self] in
            for await _ in rescans { await self?.publish() }
        }
        defer { watching.cancel() }
        while let frame = try? await world.receive() {
            let (frames, events) = node.receive(frame)
            for frame in frames { try? await world.send(frame) }
            for event in events { await handle(event) }
        }
        for (channel, viewer) in viewers {
            relays[channel]?.cancel()
            await viewer.close()
        }
        viewers.removeAll()
        relays.removeAll()
    }

    /// Sends the sessions, sealed to each trusted controller, when they changed since the last time.
    func publish() async {
        let sessions = world.sessions()
        guard sessions != published else { return }
        let controllers = world.trusted()
        guard !controllers.isEmpty,
            let json = try? AemiJSON.JSONEncoder().encodeToBytes(["sessions": sessions]),
            let frame = try? GatewayNode.list(json, to: controllers)
        else { return }
        guard (try? await world.send(frame)) != nil else { return }
        published = sessions
    }

    private func handle(_ event: GatewayNode.Event) async {
        switch event {
            case .attach(let channel, let size, let session, let controller):
                await attach(channel, size: size, session: session, controller: controller)
            case .start(let channel, _, _, let controller):
                world.audit("start refused", controller)
                for frame in node.refuse(channel, "starting a session from the gateway is not available yet") {
                    try? await world.send(frame)
                }
            case .input(let channel, let bytes): await forward(.input(bytes), on: channel)
            case .resize(let channel, let size): await forward(.resize(size), on: channel)
            case .closed(let channel):
                relays.removeValue(forKey: channel)?.cancel()
                await viewers.removeValue(forKey: channel)?.close()
        }
    }

    private func attach(_ channel: UInt32, size: ChannelMessage.Size, session: String, controller: String) async {
        guard world.sessions().contains(where: { $0.id == session }), let viewer = await world.dial(session) else {
            world.audit("attach refused", controller)
            for frame in node.refuse(channel, "no shared session \(session) on this computer") {
                try? await world.send(frame)
            }
            return
        }
        world.audit("attached \(session)", controller)
        viewers[channel] = viewer
        guard (try? await viewer.send(NoiseFraming.frame(ChannelMessage.attach(size, session: session).bytes))) != nil
        else {
            await viewerEnded(channel, "the session's screen could not be reached")
            return
        }
        relays[channel] = Task { [weak self] in
            var framing = NoiseFraming()
            while let piece = try? await viewer.receive() {
                for bytes in framing.read(piece) {
                    guard let message = try? ChannelMessage(parsing: bytes) else { continue }
                    await self?.fromViewer(message, on: channel)
                }
            }
            await self?.viewerEnded(channel, "the session's screen let this viewer go")
        }
    }

    private func fromViewer(_ message: ChannelMessage, on channel: UInt32) async {
        let frames: [RelayFrame]
        switch message {
            case .output(let bytes): frames = node.output(bytes, on: channel)
            case .refused(let words), .ended(let words):
                // The channel ends here; the relay that brought this finds it gone and says nothing more.
                guard let viewer = viewers.removeValue(forKey: channel) else { return }
                relays.removeValue(forKey: channel)
                await viewer.close()
                if case .refused = message {
                    frames = node.refuse(channel, words)
                } else {
                    frames = node.ended(channel, words)
                }
            default: return
        }
        for frame in frames { try? await world.send(frame) }
    }

    private func viewerEnded(_ channel: UInt32, _ words: String) async {
        guard let viewer = viewers.removeValue(forKey: channel) else { return }
        relays.removeValue(forKey: channel)
        await viewer.close()
        for frame in node.ended(channel, words) { try? await world.send(frame) }
    }

    private func forward(_ message: ChannelMessage, on channel: UInt32) async {
        guard let viewer = viewers[channel], let bytes = try? NoiseFraming.frame(message.bytes) else { return }
        try? await viewer.send(bytes)
    }
}
