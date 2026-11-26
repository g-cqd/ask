/// One relay frame of the gateway protocol (`docs/protocol/gateway.md`): what the gateway reads, inside a node's Noise channel or as
/// a controller's WebSocket message. A kind, a channel, a body, every integer big-endian. Parsing is strict: anything the document
/// does not allow is refused, and the connection ends with `close` reason 4.
package struct RelayFrame: Sendable, Equatable {
    package enum Kind: UInt8, Sendable {
        case hello = 0x01
        case list = 0x02
        case lists = 0x03
        case open = 0x10
        case data = 0x11
        case close = 0x12
        case ping = 0x20
        case pong = 0x21

        /// Whether frames of this kind travel on channel 0, the connection's own.
        var isConnectionLevel: Bool {
            switch self {
                case .hello, .list, .lists, .ping, .pong: true
                case .open, .data, .close: false
            }
        }
    }

    /// Why a frame was refused.
    package enum Refusal: Error, Equatable {
        case tooShort, tooLong
        case unknownKind(UInt8)
        case wrongChannel, malformedBody
    }

    /// The largest body: a Noise message's 65,535 bytes less this header's 5 and Noise's 16-byte tag.
    package static let maximumBody = 65_519

    package let kind: Kind
    package let channel: UInt32
    package let body: [UInt8]

    /// A frame, checked as a parsed one is.
    package init(kind: Kind, channel: UInt32 = 0, body: [UInt8] = []) throws(Refusal) {
        guard body.count <= Self.maximumBody else { throw .tooLong }
        guard kind.isConnectionLevel == (channel == 0) else { throw .wrongChannel }
        try Self.checkShape(kind, body)
        self.kind = kind
        self.channel = channel
        self.body = body
    }

    /// The frame parsed from `bytes`, refused unless it is exactly one well-formed frame.
    package init(parsing bytes: some Collection<UInt8>) throws(Refusal) {
        let bytes = Array(bytes)
        guard bytes.count >= 5 else { throw .tooShort }
        guard let kind = Kind(rawValue: bytes[0]) else { throw .unknownKind(bytes[0]) }
        let channel = RelayBytes.readU32(bytes.dropFirst())
        try self.init(kind: kind, channel: channel, body: Array(bytes[5...]))
    }

    /// The frame's bytes.
    package var bytes: [UInt8] {
        [
            kind.rawValue, UInt8(channel >> 24), UInt8(truncatingIfNeeded: channel >> 16),
            UInt8(truncatingIfNeeded: channel >> 8),
            UInt8(truncatingIfNeeded: channel)
        ] + body
    }

    /// The body each kind must have, as the document gives it.
    private static func checkShape(_ kind: Kind, _ body: [UInt8]) throws(Refusal) {
        let valid: Bool
        switch kind {
            case .hello: valid = body.count == 3 && (body[2] == 1 || body[2] == 2)
            case .list, .data: valid = !body.isEmpty
            case .lists: valid = listsAreWellFormed(body)
            // At least an IK first message: an ephemeral key, the sealed static key and the sealed payload (32 + 48 + 16 bytes).
            // From a controller the node's key comes first; the gateway, which knows the direction, checks that.
            case .open: valid = body.count >= 96
            case .close:
                valid =
                    !body.isEmpty && body[0] <= 4 && body.count <= 257
                    && String(validating: body.dropFirst(), as: UTF8.self) != nil
            case .ping, .pong: valid = body.count == 8
        }
        guard valid else { throw .malformedBody }
    }

    /// `lists`: entries of a 32-byte key, a u32 length and that many bytes, exactly filling the body.
    private static func listsAreWellFormed(_ body: [UInt8]) -> Bool {
        var rest = body[...]
        while !rest.isEmpty {
            guard rest.count >= 36 else { return false }
            let length = Int(RelayBytes.readU32(rest.dropFirst(32)))
            rest = rest.dropFirst(36)
            guard length > 0, rest.count >= length else { return false }
            rest = rest.dropFirst(length)
        }
        return true
    }
}
