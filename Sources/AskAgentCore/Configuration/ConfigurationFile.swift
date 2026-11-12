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
    public var sessionEncryption: SessionEncryptionMode?  // roadmap 0182, ADR-0138
    public var sessionCompression: Bool?  // roadmap 0182
    public var sessionPassword: SessionPasswordMode?  // roadmap 0182
    public var taskScope: TaskScope?  // roadmap 0179, ADR-0140
    public var credentials: CredentialStorage?  // roadmap 0110; the person's own file only
    public var approvals: ApprovalsSection?  // roadmap 0134; the person's own file only
    public var modelScopes: [ModelScope]?  // roadmap 0094; the person's own file only
    public var hooks: HooksSection?  // roadmap 0192; the person's own file only
    public var threads: ThreadsSection?  // roadmap 0195
    public var agents: AgentsSection?  // roadmap 0063, ADR-0146; a project's may only turn them off
    public var presets: [String]?  // roadmap 0190: sets of MCP servers ask knows, added to `mcp`
    public var openers: OpenersSection?  // roadmap 0216, ADR-0148; the person's own file only
    public var jobs: JobsSection?  // t232: how many finished jobs are kept

    /// The keys ask knows, in the order `ask config` shows them.
    // @dl:accept -- the list of keys is data; the sandbox policy's list of names is other data
    public static let keys = [
        // @dl:accept -- the list of keys is data, like the sandbox policy's lists of paths
        "model", "provider", "thinking", "maxTurns", "compactAt", "keepAwake", "keepDisplayAwake", "credentials",
        "approvals", "modelScopes", "sessionEncryption", "sessionCompression", "sessionPassword", "taskScope",
        "hooks", "threads", "agents", "sandbox", "ui", "skills", "presets", "mcp", "environment", "openers",
        "jobs"
    ]

    /// A file with these values.
    public init(
        model: String? = nil,
        provider: String? = nil,
        maxTurns: Int? = nil,
        // @dl:accept -- an initializer that takes every key, like each section's own
        compactAt: CompactionThreshold? = nil,
        // @dl:accept -- an initializer that takes every key; adding a section adds a parameter
        sandbox: SandboxSection? = nil,
        ui: UISection? = nil,
        thinking: ThinkingLevel? = nil,
        // @dl:accept -- configuration's optional section parameters are not agent-loop settings; no shared initializer contract
        skills: SkillsSection? = nil,
        // @dl:accept -- configuration's optional section parameters are not agent-loop settings; no shared initializer contract
        mcp: MCPSection? = nil,
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
        _ bytes: [UInt8],
        path: String,
        isProject: Bool = false
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
        try validateHooks(file.hooks, path: path, isProject: isProject)
        try validateThreads(file.threads, path: path)
        try validateAgents(file.agents, path: path, isProject: isProject)
        try validateOpeners(file.openers, path: path, isProject: isProject)
        file.mcp = try MCPPresets.adding(file.presets, to: file.mcp, path: path)
        try validateMCP(file.mcp, path: path, isProject: isProject)
        try validateEnvironment(file.environment, path: path, isProject: isProject)
        if isProject, file.approvals != nil {
            throw .outOfRange(
                path: path,
                key: "approvals",
                reason: "says which calls ask you first: only your own config file can choose that"
            )
        }
        try validateModelScopes(file.modelScopes, path: path, isProject: isProject)
        if isProject, file.credentials != nil {
            throw .outOfRange(
                path: path,
                key: "credentials",
                reason: "says where your keys are kept: only your own config file can choose that"
            )
        }
        try validateCounts(file, path: path)
        return file
    }

    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Calls `body` with each key of the object being decoded, and the container to read its value from.
    static func eachKey(
        of decoder: any Decoder,
        _ body: (Key, KeyedDecodingContainer<Key>) throws -> Void
    ) throws {
        let container = try decoder.container(keyedBy: Key.self)
        // @dl:accept -- the walk the key tables share; the analyzer matches it against their closing lines
        for key in container.allKeys { try body(key, container) }
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
                    case "sessionEncryption", "sessionCompression", "sessionPassword", "taskScope":
                        try file.decodeSessionKey(key, in: container)
                    case "keepDisplayAwake":
                        file.keepDisplayAwake = try ConfigurationFile.decodeSwitch(
                            container,
                            key: key,
                            name: "keepDisplayAwake"
                        )
                    case "credentials":
                        file.credentials = try ConfigurationFile.decodeChoice(
                            container,
                            key: key,
                            as: CredentialStorage.self
                                // @dl:accept -- each key decodes its own choice through the shared helper; the rows are the data
                        )
                    // @dl:accept -- the key tables are the data, and the walk over them is already shared
                    case "sandbox": file.sandbox = try container.decode(SandboxDecoded.self, forKey: key).section
                    case "ui": file.ui = try container.decode(UIDecoded.self, forKey: key).section
                    case "skills": file.skills = try container.decode(SkillsDecoded.self, forKey: key).section
                    // @dl:accept -- the key tables are the data, and the walk over them is already shared
                    case "mcp": file.mcp = try container.decode(MCPDecoded.self, forKey: key).section
                    case "presets": file.presets = try container.decode([String].self, forKey: key)
                    case "approvals": file.approvals = try container.decode(ApprovalsDecoded.self, forKey: key).section
                    case "hooks": file.hooks = try container.decode(HooksDecoded.self, forKey: key).section
                    case "threads": file.threads = try container.decode(ThreadsDecoded.self, forKey: key).section
                    case "agents": file.agents = try container.decode(AgentsDecoded.self, forKey: key).section
                    case "openers": file.openers = try container.decode(OpenersDecoded.self, forKey: key).section
                    case "jobs": file.jobs = try container.decode(JobsDecoded.self, forKey: key).section
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
