/// Whether a row may hold a link, read from its bytes, before ``PathLinks`` and ``AddressLinks`` walk it character by character
/// (roadmap 0152): most rows hold none, and a code row's `:` or `//` used to send it through both. Each test only skips a row that
/// they would find nothing in: every pattern they match starts with ASCII bytes these look for, and a character that matches one of
/// them is that one ASCII byte, never a byte followed by a combining mark.
enum LinkCandidates {
    private static let slash = UInt8(ascii: "/")
    private static let tilde = UInt8(ascii: "~")
    private static let at = UInt8(ascii: "@")

    /// Whether `text` may hold a path or an address.
    static func mayHoldLink(_ text: String) -> Bool { mayHoldPath(text) || mayHoldAddress(text) }

    /// Whether `text` has a `/` not followed by another `/`, or a `~/`, at the start or after what may stand before a path.
    static func mayHoldPath(_ text: String) -> Bool {
        let view = text.utf8
        let bytes = view.span
        var index = 0
        while index + 1 < bytes.count {
            let byte = bytes[index]
            if byte == slash || byte == tilde, index == 0 || isBeforePath(bytes[index - 1]) {
                let next = bytes[index + 1]
                // A `/` after the slash is a character of its own unless a non-ASCII byte, a mark, joins it.
                if byte == tilde
                    ? next == slash : (next != slash || index + 2 < bytes.count && bytes[index + 2] >= 0x80)
                {
                    return true
                }
            }
            index += 1
        }
        return false
    }

    /// Whether `text` has an `@` after what an email's local part ends with, or a scheme an address starts with.
    static func mayHoldAddress(_ text: String) -> Bool {
        let view = text.utf8
        let bytes = view.span
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
                case at where index > 0 && isLocal(bytes[index - 1]): return true
                case UInt8(ascii: "h")
                where starts(bytes, at: index, with: "http://") || starts(bytes, at: index, with: "https://"):
                    return true
                case UInt8(ascii: "m") where starts(bytes, at: index, with: "mailto:"): return true
                default: break
            }
            index += 1
        }
        return false
    }

    private static func starts(_ bytes: Span<UInt8>, at index: Int, with prefix: StaticString) -> Bool {
        guard index + prefix.utf8CodeUnitCount <= bytes.count else { return false }
        var offset = 0
        while offset < prefix.utf8CodeUnitCount {
            if bytes[index + offset] != prefix.utf8Start[offset] { return false }
            offset += 1
        }
        return true
    }

    /// `PathLinks`' `before`: a space, a tab, a quote, a bracket, `=`, `<` or a backtick.
    private static func isBeforePath(_ byte: UInt8) -> Bool {
        switch byte {
            case 0x20, 0x09, 0x22, 0x27, 0x28, 0x5B, 0x3D, 0x3C, 0x60: true
            default: false
        }
    }

    /// `AddressLinks`' local part: an ASCII letter or digit, or `.`, `_`, `%`, `+`, `-`.
    private static func isLocal(_ byte: UInt8) -> Bool {
        switch byte {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x2E, 0x5F, 0x25, 0x2B, 0x2D: true
            default: false
        }
    }
}
