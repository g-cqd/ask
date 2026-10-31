internal import AemiJSON
public import AskAI
internal import Foundation

/// One `config.json`: JSON or JSON5 in a file named `.json` (ADR-0030). Every key is optional; an absent key leaves the layer below.
///
/// Read with AemiJSON's JSON5 mode, which parses plain JSON identically, and with duplicate keys refused: in a
/// configuration file a repeated key is a typo that would silently override. Unknown keys are refused too.
public struct ConfigurationFile: Sendable, Equatable {
    public var model: String?
    public var provider: String?
    public var thinking: ThinkingLevel?
    public var maxTurns: Int?
    public var compactAt: CompactionThreshold?
    public var sandbox: SandboxSection?
    public var ui: UISection?
    public var skills: SkillsSection?
    public var mcp: MCPSection?
    public var environment: EnvironmentSection?
    /// What reading it noticed: old setting names read as new ones (roadmap 0154).
    public var notices: [String] = []
    public var keepAwake: KeepAwakeMode?  // roadmap 0090; not in the initializer, set after it
    public var keepDisplayAwake: Bool?  // roadmap 0154
    public var credentials: CredentialStorage?  // roadmap 0110; the person's own file only
    public var approvals: ApprovalsSection?  // roadmap 0134; the person's own file only
    public var modelScopes: [ModelScope]?  // roadmap 0094; the person's own file only

    /// The keys ask knows, in the order `ask config` shows them.
    // @dl:accept -- the list of keys is data; the sandbox policy's list of names is other data
    public static let keys = [
        // @dl:accept -- the list of keys is data, like the sandbox policy's lists of paths
        "model", "provider", "thinking", "maxTurns", "compactAt", "keepAwake", "keepDisplayAwake", "credentials",
        "approvals", "modelScopes",
        "sandbox", "ui", "skills", "mcp", "environment"
    ]

    /// A file with these values.
    public init(
        model: String? = nil, provider: String? = nil, maxTurns: Int? = nil, compactAt: CompactionThreshold? = nil,
        // @dl:accept -- an initializer that takes every key; adding a section adds a parameter
        sandbox: SandboxSection? = nil, ui: UISection? = nil, thinking: ThinkingLevel? = nil,
        // @dl:accept -- configuration's optional section parameters are not agent-loop settings; no shared initializer contract
        skills: SkillsSection? = nil, mcp: MCPSection? = nil,
        environment: EnvironmentSection? = nil  // @dl:accept -- an initializer that takes every key
    ) {
        // @dl:accept -- member assignments in configuration section initializers
        self.model = model
        self.provider = provider
        self.thinking = thinking
        self.maxTurns = maxTurns
        self.compactAt = compactAt
        self.sandbox = sandbox
        self.ui = ui
        self.skills = skills
        self.mcp = mcp
        self.environment = environment
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
        var file: ConfigurationFile
        var read = bytes
        do {
            let (renamed, notices) = try renamingOldNames(in: bytes, path: path)
            read = renamed
            file = try decoder.decode(Decoded.self, from: renamed).file
            file.notices = notices
        } catch let unknown as UnknownKey {
            throw .unknownKey(path: path, key: unknown.key, known: keys)
        } catch let bad as BadValue {
            throw .outOfRange(path: path, key: bad.key, reason: bad.reason)
        } catch {
            if let refusal = refusal(of: error, in: read, path: path) { throw refusal }
            let (line, column) = position(of: error, in: bytes)
            throw .invalid(path: path, line: line, column: column, reason: reason(of: error))
        }
        try validateSandbox(file.sandbox, path: path, isProject: isProject)
        try validateSkills(file.skills, path: path, isProject: isProject)
        try validateMCP(file.mcp, path: path, isProject: isProject)
        try validateEnvironment(file.environment, path: path, isProject: isProject)
        if isProject, file.approvals != nil {
            throw .outOfRange(
                path: path, key: "approvals",
                reason: "says which calls ask you first: only your own config file can choose that")
        }
        try validateModelScopes(file.modelScopes, path: path, isProject: isProject)
        if isProject, file.credentials != nil {
            throw .outOfRange(
                path: path, key: "credentials",
                reason: "says where your keys are kept: only your own config file can choose that")
        }
        for (key, count) in [
            ("ui.scrollLines", file.ui?.scrollLines), ("ui.inputRows", file.ui?.promptRows),
            ("ui.fold.codeLines", file.ui?.codeFoldLines)
        ] {
            if let count, count < 1 { throw .outOfRange(path: path, key: key, reason: "must be at least 1") }
        }
        if let turns = file.maxTurns, turns < 1 {
            throw .outOfRange(path: path, key: "maxTurns", reason: "must be at least 1")
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
                    case "readable": section.allowRead = try container.decode([String].self, forKey: key)
                    case "writable": section.allowWrite = try container.decode([String].self, forKey: key)
                    case "hide": section.denyRead = try container.decode([String].self, forKey: key)
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
                    case "thinking":
                        file.thinking = try ConfigurationFile.decodeChoice(container, key: key, as: ThinkingLevel.self)
                    case "maxTurns": file.maxTurns = try ConfigurationFile.decodeMaxTurns(container, key: key)
                    case "compactAt": file.compactAt = try ConfigurationFile.decodeCompactAt(container, key: key)
                    case "keepAwake":
                        file.keepAwake = try ConfigurationFile.decodeChoice(container, key: key, as: KeepAwakeMode.self)
                    case "keepDisplayAwake":
                        file.keepDisplayAwake = try ConfigurationFile.decodeSwitch(
                            container, key: key, name: "keepDisplayAwake")
                    case "credentials":
                        file.credentials = try ConfigurationFile.decodeChoice(
                            container, key: key, as: CredentialStorage.self)
                    case "sandbox": file.sandbox = try container.decode(SandboxDecoded.self, forKey: key).section
                    case "ui": file.ui = try container.decode(UIDecoded.self, forKey: key).section
                    case "skills": file.skills = try container.decode(SkillsDecoded.self, forKey: key).section
                    case "mcp": file.mcp = try container.decode(MCPDecoded.self, forKey: key).section
                    case "approvals": file.approvals = try container.decode(ApprovalsDecoded.self, forKey: key).section
                    case "modelScopes":
                        file.modelScopes = try container.decode([ModelScopeDecoded].self, forKey: key).map(\.scope)
                    case "environment":
                        file.environment = try container.decode(EnvironmentDecoded.self, forKey: key).section
                    default: throw UnknownKey(key: key.stringValue)
                }
            }
        }
    }
}
