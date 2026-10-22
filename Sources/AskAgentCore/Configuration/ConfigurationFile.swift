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
    public var sandbox: SandboxSection?
    public var ui: UISection?

    /// The keys ask knows, in the order `ask config` shows them.
    public static let keys = ["model", "provider", "maxTurns", "compactAt", "sandbox", "ui"]

    /// A file with these values.
    public init(
        model: String? = nil, provider: String? = nil, maxTurns: Int? = nil, compactAt: Int? = nil,
        sandbox: SandboxSection? = nil, ui: UISection? = nil
    ) {
        self.model = model
        self.provider = provider
        self.maxTurns = maxTurns
        self.compactAt = compactAt
        self.sandbox = sandbox
        self.ui = ui
    }

    /// Whether the file sets the key `name`.
    public func sets(_ name: String) -> Bool {
        switch name {
            case "model": model != nil
            case "provider": provider != nil
            case "maxTurns": maxTurns != nil
            case "compactAt": compactAt != nil
            case "sandbox": sandbox != nil
            case "ui": ui != nil
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
    /// - Parameters:
    ///   - bytes: the file's contents.
    ///   - path: named in any error.
    ///   - isProject: whether the file belongs to a project rather than the user. A project's file may narrow the
    ///     sandbox but not widen it.
    /// - Returns: the validated file.
    /// - Throws: ``ConfigurationError``.
    public static func parse(
        _ bytes: [UInt8], path: String, isProject: Bool = false
    ) throws(ConfigurationError) -> ConfigurationFile {
        var decoder = AemiJSON.JSONDecoder()
        decoder.options = JSONParseOptions(validation: .json5, duplicateKeys: .throwError)
        let file: ConfigurationFile
        do {
            file = try decoder.decode(Decoded.self, from: bytes).file
        } catch let unknown as UnknownKey {
            throw .unknownKey(path: path, key: unknown.key, known: keys)
        } catch let bad as BadValue {
            throw .outOfRange(path: path, key: bad.key, reason: bad.reason)
        } catch {
            let (line, column) = position(of: error, in: bytes)
            throw .invalid(path: path, line: line, column: column, reason: reason(of: error))
        }
        try validateSandbox(file.sandbox, path: path, isProject: isProject)
        for (key, count) in [("ui.scrollLines", file.ui?.scrollLines), ("ui.promptRows", file.ui?.promptRows)] {
            if let count, count < 1 { throw .outOfRange(path: path, key: key, reason: "must be at least 1") }
        }
        if let turns = file.maxTurns, turns < 1 {
            throw .outOfRange(path: path, key: "maxTurns", reason: "must be at least 1")
        }
        if let tokens = file.compactAt, tokens < 0 {
            throw .outOfRange(path: path, key: "compactAt", reason: "must be 0 (only when the window is full) or more")
        }
        return file
    }

    /// The sandbox section's paths must be absolute or start with `~/`, and a project's file may not widen it.
    private static func validateSandbox(
        _ section: SandboxSection?, path: String, isProject: Bool
    ) throws(ConfigurationError) {
        guard let section else { return }
        func paths(_ settings: [PathSetting]) -> [String] {
            settings.flatMap { setting -> [String] in
                if case .paths(let paths) = setting { return paths }
                return []
            }
        }
        for (key, entries) in [
            ("sandbox.allowRead", section.allowRead), ("sandbox.denyRead", section.denyRead),
            ("sandbox.write", paths(section.write)), ("sandbox.read", paths(section.read))
        ] {
            for entry in entries where !(entry.hasPrefix("/") || entry == "~" || entry.hasPrefix("~/")) {
                throw .outOfRange(
                    path: path, key: key, reason: "has \"\(entry)\": use an absolute path, or one starting with ~/")
            }
        }
        if isProject, !section.allowRead.isEmpty {
            throw .outOfRange(
                path: path, key: "sandbox.allowRead",
                reason:
                    "can only be set in your own config file: a project that could widen the sandbox would defeat it")
        }
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

    struct UnknownKey: Error { let key: String }

    /// A write or read scope: "workspace", "anywhere", or a list of paths.
    private static func scope(_ container: KeyedDecodingContainer<Key>, _ key: Key, name: String) throws -> PathSetting
    {
        guard let one = try? container.decode(String.self, forKey: key) else {
            return .paths(try container.decode([String].self, forKey: key))
        }
        switch one {
            case "workspace": return .workspace
            case "anywhere": return .anywhere
            default: throw BadValue(key: name, value: one)
        }
    }
    /// A string that is not one of the key's choices.
    struct BadValue: Error {
        let key: String
        let value: String

        var reason: String {
            switch key {
                case "sandbox.network": "is \"\(value)\": use \"none\", \"localhost\" or \"any\""
                case "ui.tools", "ui.thinking": "is \"\(value)\": use \"folded\" or \"open\""
                default: "is \"\(value)\": use \"workspace\", \"anywhere\" or a list of paths"
            }
        }
    }

    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Calls `body` with each key of the object being decoded, and the container to read its value from.
    static func eachKey(
        of decoder: any Decoder, _ body: (Key, KeyedDecodingContainer<Key>) throws -> Void
    ) throws {
        let container = try decoder.container(keyedBy: Key.self)
        // @dl:accept -- the walk the key tables share; the analyzer matches it against their closing lines
        for key in container.allKeys { try body(key, container) }
    }

    /// The `sandbox` object: its two lists, and nothing else.
    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    private struct SandboxDecoded: Decodable {
        var section = SandboxSection()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "allowRead": section.allowRead = try container.decode([String].self, forKey: key)
                    case "denyRead": section.denyRead = try container.decode([String].self, forKey: key)
                    case "write": section.write = [try ConfigurationFile.scope(container, key, name: "sandbox.write")]
                    case "read": section.read = [try ConfigurationFile.scope(container, key, name: "sandbox.read")]
                    case "network":
                        let name = try container.decode(String.self, forKey: key)
                        guard let level = SandboxPolicy.Network(named: name) else {
                            throw BadValue(key: "sandbox.network", value: name)
                        }
                        section.network = level
                    default: throw UnknownKey(key: "sandbox." + key.stringValue)
                }
            }
        }
    }

    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    private struct Decoded: Decodable {
        var file = ConfigurationFile()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "model": file.model = try container.decode(String.self, forKey: key)
                    // @dl:accept -- the key tables are the data, and the walk over them is already shared
                    case "provider": file.provider = try container.decode(String.self, forKey: key)
                    case "maxTurns": file.maxTurns = try container.decode(Int.self, forKey: key)
                    case "compactAt": file.compactAt = try container.decode(Int.self, forKey: key)
                    case "sandbox": file.sandbox = try container.decode(SandboxDecoded.self, forKey: key).section
                    case "ui": file.ui = try container.decode(UIDecoded.self, forKey: key).section
                    default: throw UnknownKey(key: key.stringValue)
                }
            }
        }
    }
}
