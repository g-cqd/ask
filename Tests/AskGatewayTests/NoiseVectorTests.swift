internal import CryptoKit
internal import Foundation
internal import Testing

@testable import AskGateway

/// ADR-0170's channels are Noise `XX` and `IK` over `25519_ChaChaPoly_SHA256`. Checked against Cacophony's published vectors: each
/// side's every handshake and transport message, byte for byte, and the handshake hash.
struct NoiseVectorTests {
    private struct Vector: Decodable {
        struct Message: Decodable {
            let payload: String
            let ciphertext: String
        }

        let protocol_name: String  // swiftlint:disable:this identifier_name
        let init_prologue: String  // swiftlint:disable:this identifier_name
        let init_static: String  // swiftlint:disable:this identifier_name
        let init_ephemeral: String  // swiftlint:disable:this identifier_name
        let init_remote_static: String?  // swiftlint:disable:this identifier_name
        let resp_static: String  // swiftlint:disable:this identifier_name
        let resp_ephemeral: String  // swiftlint:disable:this identifier_name
        let handshake_hash: String  // swiftlint:disable:this identifier_name
        let messages: [Message]
    }

    private struct File: Decodable { let vectors: [Vector] }

    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Noise/cacophony-xx-ik.json")

    private static func vector(_ pattern: NoiseHandshake.Pattern) throws -> Vector {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: fixture))
        return try #require(
            file.vectors.first { $0.protocol_name == "Noise_\(pattern.rawValue)_25519_ChaChaPoly_SHA256" }
        )
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index ..< next], radix: 16) ?? 0)
            index = next
        }
        return out
    }

    private static func key(_ hex: String) throws -> NoiseHandshake.PrivateKey {
        try NoiseHandshake.PrivateKey(rawRepresentation: bytes(hex))
    }

    @Test(arguments: NoiseHandshake.Pattern.allCases)
    func `both sides produce the published messages and hash`(_ pattern: NoiseHandshake.Pattern) throws {
        let vector = try Self.vector(pattern)
        let respondersStatic = try Self.key(vector.resp_static)
        var initiator = try NoiseHandshake(
            pattern: pattern,
            initiator: true,
            localStatic: try Self.key(vector.init_static),
            remoteStatic: pattern == .ik ? respondersStatic.publicKey : nil,
            prologue: Self.bytes(vector.init_prologue),
            ephemeral: try Self.key(vector.init_ephemeral)
        )
        var responder = try NoiseHandshake(
            pattern: pattern,
            initiator: false,
            localStatic: respondersStatic,
            prologue: Self.bytes(vector.init_prologue),
            ephemeral: try Self.key(vector.resp_ephemeral)
        )
        let handshakeLength = pattern.messages.count
        for (index, message) in vector.messages.prefix(handshakeLength).enumerated() {
            let payload = Self.bytes(message.payload)
            let writerIsInitiator = index % 2 == 0
            let written =
                writerIsInitiator
                ? try initiator.writeMessage(payload: payload) : try responder.writeMessage(payload: payload)
            #expect(written == Self.bytes(message.ciphertext), "handshake message \(index)")
            let read = writerIsInitiator ? try responder.readMessage(written) : try initiator.readMessage(written)
            #expect(read == payload)
        }
        #expect(initiator.isComplete && responder.isComplete)
        #expect(initiator.handshakeHash == Self.bytes(vector.handshake_hash))
        #expect(responder.handshakeHash == initiator.handshakeHash)
        #expect(
            responder.remoteStatic?.rawRepresentation == (try Self.key(vector.init_static)).publicKey.rawRepresentation
        )

        var initiatorChannel = try initiator.transport()
        var responderChannel = try responder.transport()
        for (offset, message) in vector.messages.dropFirst(handshakeLength).enumerated() {
            let index = handshakeLength + offset
            let payload = Self.bytes(message.payload)
            let writerIsInitiator = index % 2 == 0
            let sealed =
                writerIsInitiator ? try initiatorChannel.seal(payload) : try responderChannel.seal(payload)
            #expect(sealed == Self.bytes(message.ciphertext), "transport message \(index)")
            let opened = writerIsInitiator ? try responderChannel.open(sealed) : try initiatorChannel.open(sealed)
            #expect(opened == payload)
        }
    }
}
