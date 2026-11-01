/// A recovery code: the 256 random bits that wrap a second copy of the user key, written in base32 (RFC 4648's alphabet, which has no
/// 0, 1 or 8 to mistake for O, I or B) in 13 groups of 4, and read back however it is typed: any case, with dashes, spaces or neither.
enum RecoveryCode {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    /// 256 bits take 52 base32 digits: 51.2, rounded up.
    static let digits = 52

    static func text(for bytes: [UInt8]) -> String {
        var digits: [Character] = []
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = buffer << 8 | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                digits.append(alphabet[(buffer >> bits) & 31])
            }
        }
        if bits > 0 { digits.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return stride(from: 0, to: digits.count, by: 4).map { String(digits[$0 ..< min($0 + 4, digits.count)]) }
            .joined(separator: "-")
    }

    static func bytes(of text: String) throws(SessionKeyError) -> [UInt8] {
        let typed = text.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard typed.count == digits else { throw .unreadableRecoveryCode }
        var bytes: [UInt8] = []
        var buffer = 0
        var bits = 0
        for character in typed {
            guard let value = alphabet.firstIndex(of: character) else { throw .unreadableRecoveryCode }
            buffer = (buffer << 5 | value) & 0xFFFF
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8(truncatingIfNeeded: buffer >> bits))
            }
        }
        return bytes
    }
}
