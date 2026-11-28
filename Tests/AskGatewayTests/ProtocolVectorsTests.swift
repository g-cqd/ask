internal import AemiJSON
internal import CryptoKit
internal import Foundation
internal import Testing

@testable import AskGateway

/// Cross-language protocol vectors (`Tests/Fixtures/Gateway/protocol-vectors.json`, ADR-0170, t151): verifies that bytes produced by
/// the browser shell's `GatewayShell/crypto.mjs` (X25519 keys, Noise IK opening, relay frames, channel messages, and Ed25519 shell
/// manifest signatures) decode and verify byte-for-byte in Swift's `AskGateway`.
@Suite("GatewayShell JavaScript wire vectors match Swift AskGateway byte for byte")
struct ProtocolVectorsTests {
    private struct Vectors: Decodable {
        struct Messages: Decodable {
            let attachHex: String
            let startHex: String
            let inputHex: String
            let resizeHex: String
        }
        struct ManifestVector: Decodable {
            let ed25519SeedHex: String
            let ed25519PublicBase64: String
            let manifestJson: String
            let signatureHex: String
        }
        let controllerSeedHex: String
        let controllerPublicHex: String
        let controllerEphemeralSeedHex: String
        let nodeSeedHex: String
        let nodePublicHex: String
        let ikFirstMessageHex: String
        let openRelayFrameHex: String
        let channelMessages: Messages
        let shellManifest: ManifestVector
    }

    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Gateway/protocol-vectors.json")

    private static func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let next = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i ..< next], radix: 16) ?? 0)
            i = next
        }
        return out
    }

    @Test func `JavaScript X25519, Noise IK, RelayFrame, ChannelMessage and Ed25519 vectors verify in Swift`() throws {
        let raw = Array(try Data(contentsOf: Self.fixtureURL))
        let v = try AemiJSON.JSONDecoder().decode(Vectors.self, from: raw)

        let ctrlPriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Self.hex(v.controllerSeedHex))
        let nodePriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Self.hex(v.nodeSeedHex))
        #expect(Array(ctrlPriv.publicKey.rawRepresentation) == Self.hex(v.controllerPublicHex))
        #expect(Array(nodePriv.publicKey.rawRepresentation) == Self.hex(v.nodePublicHex))

        let openFrame = try RelayFrame(parsing: Self.hex(v.openRelayFrameHex))
        #expect(openFrame.kind == .open && openFrame.channel == 7)
        #expect(Array(openFrame.body.prefix(32)) == Self.hex(v.nodePublicHex))
        #expect(Array(openFrame.body.dropFirst(32)) == Self.hex(v.ikFirstMessageHex))

        let (nodeChannel, _) = try NodeChannel.accept(Self.hex(v.ikFirstMessageHex), nodeKey: nodePriv) {
            $0.rawRepresentation == ctrlPriv.publicKey.rawRepresentation
        }
        #expect(Array(nodeChannel.controller.rawRepresentation) == Self.hex(v.controllerPublicHex))

        #expect(
            try ChannelMessage(parsing: Self.hex(v.channelMessages.attachHex))
                == .attach(ChannelMessage.Size(columns: 120, rows: 40)!, session: "4242")
        )
        #expect(
            try ChannelMessage(parsing: Self.hex(v.channelMessages.startHex))
                == .start(ChannelMessage.Size(columns: 100, rows: 30)!, folder: "/srv/work")
        )
        #expect(
            try ChannelMessage(parsing: Self.hex(v.channelMessages.inputHex))
                == .input(Array("ls\r".utf8))
        )
        #expect(
            try ChannelMessage(parsing: Self.hex(v.channelMessages.resizeHex))
                == .resize(ChannelMessage.Size(columns: 132, rows: 50)!)
        )

        let edPriv = try Curve25519.Signing.PrivateKey(rawRepresentation: Self.hex(v.shellManifest.ed25519SeedHex))
        #expect(edPriv.publicKey.rawRepresentation.base64EncodedString() == v.shellManifest.ed25519PublicBase64)
        let signedPayload = Data(ShellManifest.domainPrefix + Array(v.shellManifest.manifestJson.utf8))
        #expect(edPriv.publicKey.isValidSignature(Data(Self.hex(v.shellManifest.signatureHex)), for: signedPayload))
    }
}
