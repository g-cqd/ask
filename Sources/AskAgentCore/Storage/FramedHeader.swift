internal import CryptoKit

/// A framed file's header: what the frames are, and, for an encrypted file, the envelope its data key is wrapped in (ADR-0138, sections
/// 2 and 4; this layer stores the envelope and does not read it).
struct FramedHeader: Equatable {
    let compressed: Bool
    let encrypted: Bool
    let payload: FramedPayload
    /// Random per file, so that no two files' frames are bound to the same header.
    let fileID: [UInt8]
    let envelope: [UInt8]
    /// The header as written.
    let bytes: [UInt8]
    /// Its SHA-256, which every encrypted frame is bound to.
    let digest: [UInt8]

    init(compressed: Bool, encrypted: Bool, payload: FramedPayload, envelope: [UInt8], fileID: [UInt8]? = nil) {
        self.compressed = compressed
        self.encrypted = encrypted
        self.payload = payload
        self.envelope = envelope
        self.fileID = fileID ?? SymmetricKey(size: .bits128).withUnsafeBytes { Array($0) }
        let flags = (compressed ? FrameFormat.compressedFlag : 0) | (encrypted ? FrameFormat.encryptedFlag : 0)
        var bytes = FrameFormat.magic + [FrameFormat.version, flags, payload.rawValue] + self.fileID
        bytes += [UInt8(truncatingIfNeeded: envelope.count), UInt8(truncatingIfNeeded: envelope.count >> 8)] + envelope
        bytes += FrameFormat.le32(FrameFormat.crc32(bytes[...]))
        self.bytes = bytes
        digest = FrameFormat.digest(bytes)
    }

    /// The header at the start of `bytes`.
    static func parse(_ bytes: [UInt8]) throws(FramedFileError) -> FramedHeader {
        guard bytes.starts(with: FrameFormat.magic) else { throw .notFramed }
        guard bytes.count > 4 else { throw .truncatedHeader }
        guard bytes[4] == FrameFormat.version else { throw .unsupportedVersion(bytes[4]) }
        let fixed = FrameFormat.fixedHeaderLength
        guard bytes.count >= fixed else { throw .truncatedHeader }
        let envelopeLength = Int(bytes[fixed - 2]) | Int(bytes[fixed - 1]) << 8
        let length = fixed + envelopeLength + 4
        guard bytes.count >= length else { throw .truncatedHeader }
        guard FrameFormat.readLE32(bytes, at: length - 4) == FrameFormat.crc32(bytes[..<(length - 4)]) else {
            throw .damagedHeader
        }
        let flags = bytes[5]
        guard flags & ~(FrameFormat.compressedFlag | FrameFormat.encryptedFlag) == 0, flags != 0,
            let payload = FramedPayload(rawValue: bytes[6])
        else { throw .damagedHeader }
        let header = FramedHeader(
            compressed: flags & FrameFormat.compressedFlag != 0,
            encrypted: flags & FrameFormat.encryptedFlag != 0,
            payload: payload,
            envelope: Array(bytes[fixed ..< (fixed + envelopeLength)]),
            fileID: Array(bytes[7 ..< 23])
        )
        return header
    }
}
