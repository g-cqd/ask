internal import AemiJSON
internal import Foundation

/// One `config.json`: JSON or JSON5 in a file named `.json` (ADR-0030). Every key is optional; a key that is
/// absent leaves the layer below in force.
///
/// Read with AemiJSON's JSON5 mode, which parses plain JSON identically, and with duplicate keys refused: in a
/// configuration file a repeated key is a typo that would silently override. Unknown keys are refused too.
public struct ConfigurationFile: Sendable, Equatable {
    public var model: String?
    public var provider: String?
    public var maxTurns: Int?
    public var compactAt: Int?

    /// The keys ask knows, in the order `ask config` shows them.
    public static let keys = ["model", "provider", "maxTurns", "compactAt"]

    /// A file with these values.
    public init(model: String? = nil, provider: String? = nil, maxTurns: Int? = nil, compactAt: Int? = nil) {
        self.model = model
        self.provider = provider
        self.maxTurns = maxTurns
        self.compactAt = compactAt
    }

    /// Whether the file sets the key `name`.
    public func sets(_ name: String) -> Bool {
        switch name {
            case "model": model != nil
            case "provider": provider != nil
            case "maxTurns": maxTurns != nil
            case "compactAt": compactAt != nil
            default: false
        }
    }

    /// The file at `path`, or nil when there is none.
    /// - Throws: ``ConfigurationError`` for a file that exists but is not a valid configuration.
    public static func load(_ path: String) throws(ConfigurationError) -> ConfigurationFile? {
        guard let bytes = try ConfigurationFileReader.read(path) else { return nil }
        return try parse(bytes, path: path)
    }

    /// Parses and validates `bytes`, naming `path` in any error.
    /// - Throws: ``ConfigurationError``.
    public static func parse(_ bytes: [UInt8], path: String) throws(ConfigurationError) -> ConfigurationFile {
        var decoder = AemiJSON.JSONDecoder()
        decoder.options = JSONParseOptions(validation: .json5, duplicateKeys: .throwError)
        let file: ConfigurationFile
        do {
            file = try decoder.decode(Decoded.self, from: bytes).file
        } catch let unknown as UnknownKey {
            throw .unknownKey(path: path, key: unknown.key, known: keys)
        } catch {
            let (line, column) = position(of: error, in: bytes)
            throw .invalid(path: path, line: line, column: column, reason: reason(of: error))
        }
        if let turns = file.maxTurns, turns < 1 {
            throw .outOfRange(path: path, key: "maxTurns", reason: "must be at least 1")
        }
        if let tokens = file.compactAt, tokens < 0 {
            throw .outOfRange(path: path, key: "compactAt", reason: "must be 0 (only when the window is full) or more")
        }
        return file
    }

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

    private struct UnknownKey: Error { let key: String }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct Decoded: Decodable {
        var file = ConfigurationFile()
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            for key in container.allKeys {
                switch key.stringValue {
                    case "model": file.model = try container.decode(String.self, forKey: key)
                    case "provider": file.provider = try container.decode(String.self, forKey: key)
                    case "maxTurns": file.maxTurns = try container.decode(Int.self, forKey: key)
                    case "compactAt": file.compactAt = try container.decode(Int.self, forKey: key)
                    default: throw UnknownKey(key: key.stringValue)
                }
            }
        }
    }
}
