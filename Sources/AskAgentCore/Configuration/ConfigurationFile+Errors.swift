internal import AemiJSON
internal import AskAI
internal import Foundation

// What a parse error says and where it points, apart from ConfigurationFile.swift to keep each file under
// the 250-line ceiling.
extension ConfigurationFile {
    /// An error in words: a parser's `unexpectedCharacter(93, at: 28)` as "unexpected ']'".
    static func reason(of error: any Error) -> String {
        let text = String(describing: error)
        if let range = text.range(of: #"unexpectedCharacter\(\d+"#, options: .regularExpression),
            let byte = UInt8(text[range].dropFirst("unexpectedCharacter(".count)), byte >= 0x20, byte < 0x7F
        {
            return "unexpected '\(Character(UnicodeScalar(byte)))'"
        }
        if text.hasPrefix("unexpectedEndOfInput") { return "the file ends in the middle of a value" }
        return text
    }

    /// The 1-based line and column of the byte offset a parse error names (`at: N`), when it names one.
    static func position(of error: any Error, in bytes: [UInt8]) -> (Int?, Int?) {
        let text = String(describing: error)
        guard let range = text.range(of: #"at: \d+"#, options: .regularExpression),
            let offset = Int(text[range].dropFirst(4)), offset <= bytes.count
        else { return (nil, nil) }
        var line = 1
        var column = 1
        for byte in bytes[..<offset] {
            if byte == 0x0A {
                line += 1
                column = 1
            } else if byte & 0xC0 != 0x80 {
                column += 1
            }
        }
        return (line, column)
    }

    struct UnknownKey: Error { let key: String }
}
