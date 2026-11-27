/// The few DER encodings an RSA public key needs.
enum DER {
    static func sequence(_ content: [UInt8]) -> [UInt8] { [0x30] + length(content.count) + content }

    /// A positive INTEGER: leading zeros dropped, one put back when the high bit is set.
    static func integer(_ bytes: [UInt8]) -> [UInt8] {
        var value = Array(bytes.drop { $0 == 0 })
        if value.isEmpty { value = [0] }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return [0x02] + length(value.count) + value
    }

    static func length(_ count: Int) -> [UInt8] {
        guard count >= 0x80 else { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var rest = count
        while rest > 0 {
            bytes.insert(UInt8(rest & 0xFF), at: 0)
            rest >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
