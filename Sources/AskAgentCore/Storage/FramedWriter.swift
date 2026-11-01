internal import CryptoKit

/// Appends records to a framed file (ADR-0138): each ``append(_:)`` returns the bytes to append, one frame, which the caller writes and
/// flushes as a session file writes a record. One owner, as the stream it compresses with is.
struct FramedWriter: ~Copyable {
    /// The file's header: the first bytes of a new file.
    let header: FramedHeader
    private let key: SymmetricKey?
    private var deflater: Deflater?
    private var index: Int

    /// A writer for a new file, compressed or not, encrypted under `key` when one is given; `envelope` is stored in the header as is.
    init(compressed: Bool, key: SymmetricKey?, payload: FramedPayload = .json, envelope: [UInt8] = [])
        throws(FramedFileError)
    {
        let deflater = compressed ? try Deflater() : nil
        header = FramedHeader(compressed: compressed, encrypted: key != nil, payload: payload, envelope: envelope)
        self.key = key
        self.deflater = deflater
        index = 0
    }

    /// A writer that continues a file read cleanly, after its last frame.
    init(resuming read: FramedRead, key: SymmetricKey?) throws(FramedFileError) {
        guard read.ending == .clean else { throw .notResumable }
        guard !read.header.encrypted || key != nil else { throw .needsKey }
        let deflater = read.header.compressed ? try Deflater() : nil
        header = read.header
        self.key = read.header.encrypted ? key : nil
        self.deflater = deflater
        index = read.frameCount
    }

    /// The bytes that append `record`: its frame.
    mutating func append(_ record: [UInt8]) throws(FramedFileError) -> [UInt8] {
        var body = record
        if let deflater {
            body = try deflater.compress(record)
            if key == nil { body += FrameFormat.le32(FrameFormat.crc32(record[...])) }
        }
        return try frame(.record, body: body)
    }

    private mutating func frame(_ kind: FrameFormat.Kind, body: [UInt8]) throws(FramedFileError) -> [UInt8] {
        var sealed = body
        if let key {
            let data = FrameFormat.authenticatedData(headerDigest: header.digest, index: index)
            guard let box = try? AES.GCM.seal(body, using: key, authenticating: data), let combined = box.combined
            else {
                throw .compression
            }
            sealed = Array(combined)
        }
        index += 1
        return FrameFormat.frameHeader(kind: kind, length: sealed.count) + sealed
    }
}
