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

    /// Everything `step` (`deflate` or `inflate`, with a sync flush) makes of `input`; nil when zlib reports an error, or the input is not
    /// used up.
    func run(_ input: ArraySlice<UInt8>, step: (UnsafeMutablePointer<z_stream>) -> Int32) -> [UInt8]? {
        var input = Array(input)
        var output: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 16_384)
        return input.withUnsafeMutableBufferPointer { input -> [UInt8]? in
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
                guard status == Z_OK || status == Z_BUF_ERROR else { return nil }
                output += chunk[..<(chunk.count - Int(unsafe stream.pointee.avail_out))]
            } while unsafe stream.pointee.avail_out == 0
            return unsafe stream.pointee.avail_in == 0 ? output : nil
        }
    }
}
