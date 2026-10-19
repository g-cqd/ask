internal import CryptoKit
internal import Foundation

/// `application/x-www-form-urlencoded`, as browsers' `URLSearchParams` writes it.
enum FormEncoding {
    /// `pairs` as a query or form body, in order, with every reserved character escaped.
    /// - Parameters:
    ///   - pairs: the names and values.
    ///   - space: how a space is written: `+` as a form does, or `%20` for a parser that wants a percent escape.
    /// - Returns: `name=value` joined by `&`.
    static func query(_ pairs: [(String, String)], spaceAs space: String = "+") -> String {
        pairs.map { name, value in
            encode(name).replacingOccurrences(of: "+", with: space) + "="
                + encode(value).replacingOccurrences(of: "+", with: space)
        }
        .joined(separator: "&")
    }

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
