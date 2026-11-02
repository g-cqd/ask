internal import Compression

/// Raw deflate, as zip archives store it, through the system's Compression framework.
enum Inflate {
    /// The most a file may inflate to.
    static let limit = 4 << 20

    /// `data` inflated; nil unless it is exactly `size` bytes, at most ``limit``.
    static func raw(_ data: [UInt8], size: Int) -> [UInt8]? {
        guard size > 0, size <= limit, !data.isEmpty else { return nil }
        // One spare byte: a stream that inflates to more than `size` fills it, and is refused.
        var output = [UInt8](repeating: 0, count: size + 1)
        let written = output.withUnsafeMutableBufferPointer { out in
            data.withUnsafeBufferPointer { input in
                compression_decode_buffer(
                    out.baseAddress!,
                    out.count,
                    input.baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { return nil }
        return Array(output.prefix(size))
    }
}
