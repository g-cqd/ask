internal import CryptoKit
internal import zlib

/// The byte layout of a framed file (ADR-0138, section 2), shared by its reader and writer.
///
/// ```
/// header  "ASKF" · version · flags · payload · file id (16) · envelope length (u16) · envelope · CRC-32 of all before it
/// frame   length (u32) · kind · CRC-32 of length and kind · body
/// ```
///
/// Integers are little-endian. A compressed file is one raw deflate stream per writer: a writer that reopens the file starts a new one,
/// which the reader's stream decodes as it is, since each record ends on a sync flush's block boundary and a new stream only refers to
/// its own bytes. A frame header has its own check so that a changed length is damage, never a tear: a crash only cuts a
/// file short. An encrypted body is AES-256-GCM's nonce, ciphertext and tag, bound to the header's SHA-256 and the frame's index.
enum FrameFormat {
    static let magic: [UInt8] = Array("ASKF".utf8)
    static let version: UInt8 = 1
    static let compressedFlag: UInt8 = 1
    static let encryptedFlag: UInt8 = 2
    /// Magic, version, flags, payload, file id and envelope length: the header before its envelope.
    static let fixedHeaderLength = 4 + 1 + 1 + 1 + 16 + 2
    /// Length, kind and their CRC-32.
    static let frameHeaderLength = 9

    /// What a frame holds. One kind today; the byte leaves room for others.
    enum Kind: UInt8 {
        /// One record.
        case record = 1
    }

    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.withUnsafeBufferPointer { buffer in
            UInt32(unsafe zlib.crc32(0, buffer.baseAddress, uInt(buffer.count)))
        }
    }

    static func le32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ]
    }

    static func readLE32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0 ..< 4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << UInt32(8 * $1) }
    }

    /// The frame header for a body of `length` bytes.
    static func frameHeader(kind: Kind, length: Int) -> [UInt8] {
        let start = le32(UInt32(length)) + [kind.rawValue]
        return start + le32(crc32(start[...]))
    }

    /// What an encrypted frame is bound to: the header it belongs to, and its place in the file.
    static func authenticatedData(headerDigest: [UInt8], index: Int) -> [UInt8] {
        headerDigest + (0 ..< 8).map { UInt8(truncatingIfNeeded: UInt64(index) >> UInt64(8 * $0)) }
    }

    static func digest(_ bytes: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: bytes))
    }
}
