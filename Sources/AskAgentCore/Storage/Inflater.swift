internal import zlib

/// The reading side of ``Deflater``: one raw deflate stream, fed a frame at a time, giving back what each frame holds.
final class Inflater {
    private let stream: ZStream

    init() throws(FramedFileError) {
        stream = try ZStream(
            start: { unsafe inflateInit2_($0, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) },
            end: { unsafe inflateEnd($0) }
        )
    }

    /// What `bytes`, one frame's deflate data, decompress to, kept up to `limit` bytes; a record over it is consumed and dropped, so
    /// the frames after it still decode.
    func decompress(_ bytes: ArraySlice<UInt8>, limit: Int = .max) -> ZStream.Output {
        stream.run(bytes, limit: limit, step: { unsafe inflate($0, Z_SYNC_FLUSH) })
    }
}
