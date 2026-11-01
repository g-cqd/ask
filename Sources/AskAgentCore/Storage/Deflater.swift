internal import zlib

/// One raw deflate stream (no zlib or gzip wrapper), flushed to a byte boundary after each record (`Z_SYNC_FLUSH`), so a record's bytes
/// end where its frame ends and a reader can stop after any frame (ADR-0138, section 2). Apple's Compression framework has no such flush.
final class Deflater {
    private let stream: ZStream

    init() throws(FramedFileError) {
        stream = try ZStream(
            start: {
                unsafe deflateInit2_(
                    $0,
                    Z_DEFAULT_COMPRESSION,
                    Z_DEFLATED,
                    -MAX_WBITS,
                    8,
                    Z_DEFAULT_STRATEGY,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
            },
            end: { unsafe deflateEnd($0) }
        )
    }

    /// `record` compressed, through its sync flush.
    func compress(_ record: [UInt8]) throws(FramedFileError) -> [UInt8] {
        guard case .bytes(let bytes) = stream.run(record[...], step: { unsafe deflate($0, Z_SYNC_FLUSH) }) else {
            throw .compression
        }
        return bytes
    }
}
