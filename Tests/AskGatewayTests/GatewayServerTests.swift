internal import CryptoKit
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskGateway

/// End-to-end network test of `GatewayServer` (ADR-0170, t153): wildcard bind refusal, CIDR checks, Cloudflare Access RS256 verification
/// (including JWKS key rotation), static shell serving with CSP headers, and full WebSocket <-> `GatewayRelay` <-> TCP `NoiseLink`
/// channel routing between a controller and a node.
@Suite("GatewayServer enforces two doors, Cloudflare Access, static CSP headers and end-to-end Noise channels")
struct GatewayServerTests {
    private static let audience = "aud-gateway-test"
    private static let issuer = "https://team.cloudflareaccess.com"

    private static func token(from signer: TestRSASigner) throws -> String {
        let exp = Int(Date().timeIntervalSince1970 + 3_600)
        return try signer.sign(claimsJSON: #"{"aud":"\#(audience)","iss":"\#(issuer)","exp":\#(exp)}"#)
    }

    private static func clientWSFrame(_ payload: [UInt8]) -> [UInt8] {
        let mask: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        var header: [UInt8] = [0x82]
        if payload.count < 126 {
            header.append(0x80 | UInt8(payload.count))
        } else {
            header += [0x80 | 126, UInt8(payload.count >> 8), UInt8(truncatingIfNeeded: payload.count)]
        }
        return header + mask + payload.enumerated().map { $1 ^ mask[$0 % 4] }
    }

    private static func readServerWSBinary(_ stream: TCPStream, buffer: inout [UInt8]) async throws -> [UInt8] {
        while true {
            if buffer.count >= 2 {
                var len = Int(buffer[1] & 0x7F)
                var offset = 2
                if len == 126, buffer.count >= 4 {
                    len = (Int(buffer[2]) << 8) | Int(buffer[3])
                    offset = 4
                } else if len == 126 {
                    len = Int.max
                }
                if len < Int.max, buffer.count >= offset + len {
                    let opcode = buffer[0] & 0x0F
                    let body = Array(buffer[offset ..< offset + len])
                    buffer.removeFirst(offset + len)
                    if opcode == 0x02 { return body }
                }
            }
            guard let chunk = try await stream.receive() else { throw POSIXError(.ECONNRESET) }
            buffer += chunk
        }
    }

    private static func httpReadAll(_ stream: TCPStream) async -> String {
        var bytes: [UInt8] = []
        while let piece = try? await stream.receive() { bytes += piece }
        return String(decoding: bytes, as: UTF8.self)
    }

    @Test func `wildcard 0.0.0.0 bind is refused, and IPv4Subnet matches CIDRs accurately`() async {
        let server = GatewayServer()
        await #expect(throws: GatewayServer.Failure.wildcardNodesBindRefused) {
            _ = try await server.start(
                .init(
                    nodesHost: "0.0.0.0",
                    nodesPort: 0,
                    controllersPort: 0,
                    key: .init(),
                    enrolled: { _ in false },
                    access: AccessVerifier(mode: .insecureLocalNoAccess),
                    shell: GatewayShellFiles(directory: nil)
                )
            )
        }
        let subnet = IPv4Subnet("192.168.50.0/24")!
        #expect(subnet.contains(IPv4Subnet.ipv4("192.168.50.42")!))
        #expect(!subnet.contains(IPv4Subnet.ipv4("192.168.51.1")!))
    }

    @Test(.timeLimit(.minutes(1)))
    func `Access JWT gates HTTP and WebSocket, rotates JWKS keys, serves shell CSP, and routes end-to-end Noise IK`()
        async throws
    {
        let shellRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ask-gw-srv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: shellRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: shellRoot) }
        try Data("<html><body>ask-shell-marker</body></html>".utf8)
            .write(to: shellRoot.appendingPathComponent("index.html"))

        let signer1 = try TestRSASigner(kid: "k1")
        let signer2 = try TestRSASigner(kid: "k2")
        let jwks = Mutex(Array(#"{"keys":[\#(signer1.jwkJSON)]}"#.utf8))
        let access = AccessVerifier(
            mode: .required(issuer: Self.issuer, audience: Self.audience, fetchKeys: { jwks.withLock { $0 } })
        )

        let serverKey = Curve25519.KeyAgreement.PrivateKey()
        let nodeKey = Curve25519.KeyAgreement.PrivateKey()
        let controllerKey = Curve25519.KeyAgreement.PrivateKey()
        let enrolledRaw = nodeKey.publicKey.rawRepresentation

        let server = GatewayServer()
        let ports = try await server.start(
            .init(
                nodesHost: "127.0.0.1",
                nodesPort: 0,
                nodesSubnet: IPv4Subnet("127.0.0.0/8"),
                controllersPort: 0,
                key: serverKey,
                enrolled: { $0.rawRepresentation == enrolledRaw },
                access: access,
                shell: GatewayShellFiles(directory: shellRoot.path)
            )
        )

        let unauth = try await TCPStream.connect(host: "127.0.0.1", port: Int(ports.controllersPort))
        try await unauth.send(Array("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        #expect(await Self.httpReadAll(unauth).hasPrefix("HTTP/1.1 403 Forbidden"))
        await unauth.close()

        jwks.withLock { $0 = Array(#"{"keys":[\#(signer1.jwkJSON),\#(signer2.jwkJSON)]}"#.utf8) }
        let rotatedToken = try Self.token(from: signer2)
        let authed = try await TCPStream.connect(host: "127.0.0.1", port: Int(ports.controllersPort))
        try await authed.send(
            Array("GET / HTTP/1.1\r\nHost: localhost\r\nCf-Access-Jwt-Assertion: \(rotatedToken)\r\n\r\n".utf8)
        )
        let page = await Self.httpReadAll(authed)
        await authed.close()
        #expect(page.hasPrefix("HTTP/1.1 200 OK"))
        #expect(page.contains("Content-Security-Policy: default-src 'none'"))
        #expect(page.contains("ask-shell-marker"))

        let rogueTCP = try await TCPStream.connect(host: "127.0.0.1", port: Int(ports.nodesPort))
        _ = try? await NoiseLink.node(over: rogueTCP, key: .init(), gatewayKey: serverKey.publicKey)
        await rogueTCP.close()

        let nodeTCP = try await TCPStream.connect(host: "127.0.0.1", port: Int(ports.nodesPort))
        let nodeLink = try await NoiseLink.node(over: nodeTCP, key: nodeKey, gatewayKey: serverKey.publicKey)
        var gatewayNode = GatewayNode(key: nodeKey) {
            $0.rawRepresentation == controllerKey.publicKey.rawRepresentation
        }
        try await nodeLink.send(GatewayNode.hello)
        let listJSON = Array(
            #"{"sessions":[{"id":"42","folder":"/srv/app","label":"sonnet","started":"t"}],"folders":[]}"#.utf8
        )
        try await nodeLink.send(try GatewayNode.list(listJSON, to: [controllerKey.publicKey]))

        let ws = try await TCPStream.connect(host: "127.0.0.1", port: Int(ports.controllersPort))
        let upgrade =
            "GET /socket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
            + "Cf-Access-Jwt-Assertion: \(rotatedToken)\r\n\r\n"
        try await ws.send(Array(upgrade.utf8))
        var wsBuf: [UInt8] = []
        while !String(decoding: wsBuf, as: UTF8.self).contains("\r\n\r\n") {
            guard let piece = try await ws.receive() else {
                Issue.record("closed before 101")
                return
            }
            wsBuf += piece
        }
        let headerEnd = String(decoding: wsBuf, as: UTF8.self).range(of: "\r\n\r\n")!
        let headerLen = String(decoding: wsBuf, as: UTF8.self)[..<headerEnd.upperBound].utf8.count
        #expect(String(decoding: wsBuf[..<headerLen], as: UTF8.self).hasPrefix("HTTP/1.1 101"))
        wsBuf.removeFirst(headerLen)

        try await ws.send(Self.clientWSFrame(try RelayFrame(kind: .hello, body: [0, 1, 2]).bytes))
        let listsFrame = try RelayFrame(parsing: try await Self.readServerWSBinary(ws, buffer: &wsBuf))
        #expect(listsFrame.kind == .lists)
        #expect(try SealedList.open(Array(listsFrame.body.dropFirst(36)), with: controllerKey) == listJSON)

        let nodeTask = Task {
            while let frame = try? await nodeLink.receive() {
                let (replies, events) = gatewayNode.receive(frame)
                for reply in replies { try? await nodeLink.send(reply) }
                for event in events {
                    if case .attach(let ch, _, let session, _) = event, session == "42" {
                        for out in gatewayNode.output(Array("READY>".utf8), on: ch) {
                            try? await nodeLink.send(out)
                        }
                        return
                    }
                }
            }
        }

        var (controllerChannel, ikFirst) = try ControllerChannel.open(
            controllerKey: controllerKey,
            nodeKey: nodeKey.publicKey
        )
        let openBody = Array(nodeKey.publicKey.rawRepresentation) + ikFirst
        try await ws.send(Self.clientWSFrame(try RelayFrame(kind: .open, channel: 1, body: openBody).bytes))
        let ikAnswer = try RelayFrame(parsing: try await Self.readServerWSBinary(ws, buffer: &wsBuf))
        try controllerChannel.finish(ikAnswer.body)

        let attachSealed = try controllerChannel.send(
            .attach(ChannelMessage.Size(columns: 80, rows: 24)!, session: "42")
        )
        try await ws.send(Self.clientWSFrame(try RelayFrame(kind: .data, channel: 1, body: attachSealed).bytes))
        let screenFrame = try RelayFrame(parsing: try await Self.readServerWSBinary(ws, buffer: &wsBuf))
        #expect(try controllerChannel.receive(screenFrame.body) == .output(Array("READY>".utf8)))

        await nodeTask.value
        await ws.close()
        await nodeLink.close()
        await server.stop()
    }
}
