/// A message inside a channel's end-to-end Noise transport (`docs/protocol/gateway.md`, "Channel messages"): what a controller asks
/// of a node, and the terminal bytes the node sends back. Parsing is strict; the gateway never sees these.
package enum ChannelMessage: Sendable, Equatable {
    /// A terminal's size, 1 to 1,000 columns and rows.
    package struct Size: Sendable, Equatable {
        package let columns: UInt16
        package let rows: UInt16

        package init?(columns: UInt16, rows: UInt16) {
            guard (1 ... 1_000).contains(columns), (1 ... 1_000).contains(rows) else { return nil }
            self.columns = columns
            self.rows = rows
        }
    }

    /// Why a message was refused.
    package enum Refusal: Error, Equatable {
        case empty
        case unknownKind(UInt8)
        case malformed
    }

    case attach(Size, session: String)
    case start(Size, folder: String)
    case input([UInt8])
    case resize(Size)
    case output([UInt8])
    case ended(String)
    case refused(String)

    /// The longest session id or folder, in bytes.
    static let longestName = 1_024

    package var bytes: [UInt8] {
        switch self {
            case .attach(let size, let session): [0x01] + Self.write(size) + Array(session.utf8)
            case .start(let size, let folder): [0x02] + Self.write(size) + Array(folder.utf8)
            case .input(let bytes): [0x03] + bytes
            case .resize(let size): [0x04] + Self.write(size)
            case .output(let bytes): [0x10] + bytes
            case .ended(let words): [0x11] + Array(words.utf8)
            case .refused(let words): [0x12] + Array(words.utf8)
        }
    }

    package init(parsing bytes: [UInt8]) throws(Refusal) {
        guard let kind = bytes.first else { throw .empty }
        let body = bytes.dropFirst()
        switch kind {
            case 0x01: self = .attach(try Self.size(body), session: try Self.name(body.dropFirst(4)))
            case 0x02: self = .start(try Self.size(body), folder: try Self.name(body.dropFirst(4)))
            case 0x03:
                guard !body.isEmpty else { throw .malformed }
                self = .input(Array(body))
            case 0x04:
                guard body.count == 4 else { throw .malformed }
                self = .resize(try Self.size(body))
            case 0x10:
                guard !body.isEmpty else { throw .malformed }
                self = .output(Array(body))
            case 0x11: self = .ended(try Self.words(body))
            case 0x12: self = .refused(try Self.words(body))
            default: throw .unknownKind(kind)
        }
    }

    private static func write(_ size: Size) -> [UInt8] { RelayBytes.u16(size.columns) + RelayBytes.u16(size.rows) }

    private static func size(_ body: ArraySlice<UInt8>) throws(Refusal) -> Size {
        guard body.count >= 4,
            let size = Size(columns: RelayBytes.readU16(body), rows: RelayBytes.readU16(body.dropFirst(2)))
        else { throw .malformed }
        return size
    }

    /// A session id or folder: UTF-8, not empty, at most ``longestName`` bytes, with no control characters.
    private static func name(_ body: ArraySlice<UInt8>) throws(Refusal) -> String {
        guard !body.isEmpty, body.count <= longestName, let text = String(validating: body, as: UTF8.self),
            !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else { throw .malformed }
        return text
    }

    private static func words(_ body: ArraySlice<UInt8>) throws(Refusal) -> String {
        guard body.count <= 4_096, let text = String(validating: body, as: UTF8.self) else { throw .malformed }
        return text
    }
}
