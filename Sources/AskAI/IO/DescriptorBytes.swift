internal import Darwin

/// `read(2)` and `write(2)` of a byte array from an offset, for the loops that read or write the whole of one: an empty array has no
/// address, and reads or writes nothing rather than trapping (the swift-ci discipline's force unwraps, roadmap n41).
public enum DescriptorBytes {
    /// Writes `bytes` from `offset` to the end on `descriptor`; what `write(2)` returns, or 0 when there is nothing to write.
    // @dl:accept -- read and write mirror each other: the one difference is the buffer write(2) reads and read(2) fills
    public static func write(_ descriptor: Int32, _ bytes: [UInt8], from offset: Int) -> Int {
        bytes.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress, offset < buffer.count else { return 0 }
            return unsafe Darwin.write(descriptor, base + offset, buffer.count - offset)
        }
    }

    /// Reads into `bytes` from `offset` to the end from `descriptor`; what `read(2)` returns, or 0 when there is no room.
    public static func read(_ descriptor: Int32, into bytes: inout [UInt8], at offset: Int) -> Int {
        bytes.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress, offset < buffer.count else { return 0 }
            return unsafe Darwin.read(descriptor, base + offset, buffer.count - offset)
        }
    }
}
