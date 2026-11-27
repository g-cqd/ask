package import CryptoKit

/// The gateway server (ADR-0170): two strictly separated TCP doors around one ``GatewayRelay``.
///
/// 1. **Nodes door**: bound to one explicit LAN IPv4 address (`0.0.0.0` is refused), optionally restricted by CIDR before any byte is
///    read, then mutually authenticated with Noise `XX` against `enrolled`.
/// 2. **Controllers door**: bound only to `127.0.0.1` (for `cloudflared`), checking `Cf-Access-Jwt-Assertion` via ``AccessVerifier`` on
///    every HTTP request and WebSocket upgrade, serving ``GatewayShellFiles`` on HTTP and binary ``RelayFrame``s on `/socket`.
package actor GatewayServer {
    package enum Failure: Error, Equatable, CustomStringConvertible {
        case wildcardNodesBindRefused
        case socket(TCPStream.Failure)

        package var description: String {
            switch self {
                case .wildcardNodesBindRefused:
                    "nodes-listen must name a specific LAN IPv4 address, never 0.0.0.0"
                case .socket(let failure): failure.description
            }
        }
    }

    package struct Configuration: Sendable {
        package let nodesHost: String
        package let nodesPort: UInt16
        package let nodesSubnet: IPv4Subnet?
        package let controllersPort: UInt16
        package let key: Curve25519.KeyAgreement.PrivateKey
        package let enrolled: @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
        package let access: AccessVerifier
        package let shell: GatewayShellFiles

        package init(
            nodesHost: String,
            nodesPort: UInt16,
            nodesSubnet: IPv4Subnet? = nil,
            controllersPort: UInt16,
            key: Curve25519.KeyAgreement.PrivateKey,
            enrolled: @escaping @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool,
            access: AccessVerifier,
            shell: GatewayShellFiles
        ) {
            self.nodesHost = nodesHost
            self.nodesPort = nodesPort
            self.nodesSubnet = nodesSubnet
            self.controllersPort = controllersPort
            self.key = key
            self.enrolled = enrolled
            self.access = access
            self.shell = shell
        }
    }

    enum Peer {
        case node(NoiseLink)
        case controller(TCPStream)
    }

    var relay = GatewayRelay()
    var peers: [Int: Peer] = [:]
    var nextID = 1
    private var nodesListener: TCPListener?
    private var controllersListener: TCPListener?

    /// The bound port of the nodes door once started.
    package private(set) var nodesPort: UInt16 = 0
    /// The bound port of the controllers door (`127.0.0.1`) once started.
    package private(set) var controllersPort: UInt16 = 0

    package init() {}

    /// Starts both doors and returns `(nodesPort, controllersPort)`.
    package func start(_ configuration: Configuration) throws(Failure) -> (nodesPort: UInt16, controllersPort: UInt16) {
        guard IPv4Subnet.isSpecificBindAddress(configuration.nodesHost) else { throw .wildcardNodesBindRefused }
        let nodesDoor: TCPListener
        let controllersDoor: TCPListener
        let key = configuration.key
        let enrolled = configuration.enrolled
        let access = configuration.access
        let shell = configuration.shell
        do throws(TCPStream.Failure) {
            nodesDoor = try TCPListener(
                host: configuration.nodesHost,
                port: configuration.nodesPort,
                subnet: configuration.nodesSubnet
            ) { [weak self] stream in
                guard let self else {
                    Task { await stream.close() }
                    return
                }
                Task { await self.serveNode(stream, key: key, enrolled: enrolled) }
            }
            do throws(TCPStream.Failure) {
                controllersDoor = try TCPListener(host: "127.0.0.1", port: configuration.controllersPort) {
                    [weak self] stream in
                    guard let self else {
                        Task { await stream.close() }
                        return
                    }
                    Task { await self.serveController(stream, access: access, shell: shell) }
                }
            } catch {
                nodesDoor.stop()
                throw error
            }
        } catch {
            throw .socket(error)
        }
        nodesListener = nodesDoor
        controllersListener = controllersDoor
        self.nodesPort = nodesDoor.port
        self.controllersPort = controllersDoor.port
        return (nodesDoor.port, controllersDoor.port)
    }

    /// Stops both listeners and closes every open connection.
    package func stop() async {
        nodesListener?.stop()
        controllersListener?.stop()
        nodesListener = nil
        controllersListener = nil
        let current = peers
        peers.removeAll()
        for (_, peer) in current {
            switch peer {
                case .node(let link): await link.close()
                case .controller(let stream): await stream.close()
            }
        }
    }

    private func serveNode(
        _ stream: TCPStream,
        key: Curve25519.KeyAgreement.PrivateKey,
        enrolled: @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
    ) async {
        guard let link = try? await NoiseLink.gateway(over: stream, key: key, enrolled: enrolled) else {
            await stream.close()
            return
        }
        let id = allocate(.node(link))
        await dispatch(relay.nodeConnected(id, key: Array(link.remoteKey.rawRepresentation)))
        while let frame = try? await link.receive() {
            await dispatch(relay.receive(frame, on: id))
        }
        await dropPeer(id)
    }

    func allocate(_ peer: Peer) -> Int {
        defer { nextID += 1 }
        peers[nextID] = peer
        return nextID
    }

    func dropPeer(_ id: Int) async {
        guard let peer = peers.removeValue(forKey: id) else { return }
        let outgoing = relay.disconnected(id)
        switch peer {
            case .node(let link): await link.close()
            case .controller(let stream): await stream.close()
        }
        await dispatch(outgoing)
    }

    func dispatch(_ outgoing: [GatewayRelay.Outgoing]) async {
        for item in outgoing {
            switch item {
                case .send(let id, let frame):
                    guard let peer = peers[id] else { continue }
                    switch peer {
                        case .node(let link):
                            try? await link.send(frame)
                        case .controller(let stream):
                            try? await stream.send(WebSocketFrames.binary(frame.bytes))
                    }
                case .drop(let id, _):
                    await dropPeer(id)
            }
        }
    }
}
