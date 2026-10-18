internal import CryptoKit
internal import Foundation

/// `application/x-www-form-urlencoded`, as browsers' `URLSearchParams` writes it.
enum FormEncoding {
    static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
                case 0x2A, 0x2D, 0x2E, 0x30 ... 0x39, 0x41 ... 0x5A, 0x5F, 0x61 ... 0x7A:
                    out.append(Character(UnicodeScalar(byte)))
                case 0x20: out.append("+")
                default: out += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
            }
        }
        return out
    }
}
