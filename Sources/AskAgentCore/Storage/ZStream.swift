internal import zlib

/// A zlib stream, deflating or inflating: the state zlib keeps, at a fixed address for as long as the stream lives, and the loop that
/// feeds it input and collects its output. ``Deflater`` and ``Inflater`` are its two directions.
final class ZStream {
    private let stream: UnsafeMutablePointer<z_stream>
    private let end: (UnsafeMutablePointer<z_stream>) -> Int32

    /// A stream begun by `start` (`deflateInit2_` or `inflateInit2_`) and ended by `end`.
    init(
        start: (UnsafeMutablePointer<z_stream>) -> Int32,
        end: @escaping (UnsafeMutablePointer<z_stream>) -> Int32
    ) throws(FramedFileError) {
        let stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        unsafe stream.initialize(to: z_stream())
        guard start(stream) == Z_OK else {
            unsafe stream.deallocate()
            throw .compression
        }
        unsafe self.stream = stream
        self.end = end
    }

    deinit {
        _ = unsafe end(stream)
        unsafe stream.deallocate()
    }

    /// What running `input` through a stream gave.
    enum Output {
        case bytes([UInt8])
        /// More than the limit: the stream consumed it all, so the next input still decodes, and kept none of it.
        case tooLong
        /// zlib reported an error, or the input was not used up.
        case invalid
    }

    /// Everything `step` (`deflate` or `inflate`, with a sync flush) makes of `input`, at most `limit` bytes of it kept.
    func run(_ input: ArraySlice<UInt8>, limit: Int = .max, step: (UnsafeMutablePointer<z_stream>) -> Int32) -> Output {
        var input = Array(input)
        var output: [UInt8] = []
        var tooLong = false
        var chunk = [UInt8](repeating: 0, count: 16_384)
        return input.withUnsafeMutableBufferPointer { input -> Output in
            unsafe stream.pointee.next_in = input.baseAddress
            unsafe stream.pointee.avail_in = uInt(input.count)
            defer { unsafe stream.pointee.next_in = nil }
            repeat {
                let status = chunk.withUnsafeMutableBufferPointer { chunk in
                    unsafe stream.pointee.next_out = chunk.baseAddress
                    unsafe stream.pointee.avail_out = uInt(chunk.count)
                    return step(unsafe stream)
                }
                // Z_BUF_ERROR: nothing left to do with this input. Anything else, a stream's end included, is not what a frame holds.
                guard status == Z_OK || status == Z_BUF_ERROR else { return .invalid }
                let produced = chunk[..<(chunk.count - Int(unsafe stream.pointee.avail_out))]
                if !tooLong, output.count + produced.count > limit {
                    tooLong = true
                    output = []
                }
                if !tooLong { output += produced }
            } while unsafe stream.pointee.avail_out == 0
            guard unsafe stream.pointee.avail_in == 0 else { return .invalid }
            return tooLong ? .tooLong : .bytes(output)
        }
    }
}
