/// Big-endian integers as the gateway protocol writes them.
enum RelayBytes {
    static func u16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(truncatingIfNeeded: value)] }

    static func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ]
    }

    /// The first two bytes of `bytes`, which must hold them.
    static func readU16(_ bytes: some Collection<UInt8>) -> UInt16 {
        bytes.prefix(2).reduce(0) { $0 << 8 | UInt16($1) }
    }

    /// The first four bytes of `bytes`, which must hold them.
    static func readU32(_ bytes: some Collection<UInt8>) -> UInt32 {
        bytes.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}
