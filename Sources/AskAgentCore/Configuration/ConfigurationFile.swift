internal import AemiJSON
public import AskAI
internal import Foundation

/// One `config.json`: JSON or JSON5 in a file named `.json` (ADR-0030). Every key is optional; an absent key leaves the layer below.
///
/// Read with AemiJSON's JSON5 mode, which parses plain JSON identically, and with duplicate keys refused: in a
/// configuration file a repeated key is a typo that would silently override. Unknown keys are refused too.
public struct ConfigurationFile: Sendable, Equatable {
    public var model: String?
    // @dl:accept -- two records' stored settings (this file's and the ui section's), each a run of optional fields: alike in shape only
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
    public var keepAwake: KeepAwakeMode?  // roadmap 0090
    public var keepDisplayAwake: Bool?  // roadmap 0154
    public var sessionEncryption: SessionEncryptionMode?  // roadmap 0182, ADR-0138
    public var sessionCompression: Bool?  // roadmap 0182
    public var sessionPassword: SessionPasswordMode?  // roadmap 0182
    public var taskScope: TaskScope?  // roadmap 0179, ADR-0140
    public var codemode: Bool?  // roadmap 0012, ADR-0156
    public var credentials: CredentialStorage?  // roadmap 0110; the person's own file only
    public var approvals: ApprovalsSection?  // roadmap 0134; the person's own file only
    public var modelScopes: [ModelScope]?  // roadmap 0094; the person's own file only
    public var hooks: HooksSection?  // roadmap 0192; the person's own file only
    public var threads: ThreadsSection?  // roadmap 0195
    public var agents: AgentsSection?  // roadmap 0063, ADR-0146; a project's may only turn them off
    public var presets: [String]?  // roadmap 0190: sets of MCP servers ask knows, added to `mcp`
    public var openers: OpenersSection?  // roadmap 0216, ADR-0148; the person's own file only
    public var jobs: JobsSection?  // t232: how many finished jobs are kept
    public var policy: PolicySection?  // ADR-0168: an organisation's requirements only

    /// The keys ask knows, in the order `ask config` shows them.
    // @dl:accept -- the list of keys is data; the sandbox policy's list of names is other data
    public static let keys = [
        // @dl:accept -- the list of keys is data, like the sandbox policy's lists of paths
        "model", "provider", "thinking", "maxTurns", "compactAt", "keepAwake", "keepDisplayAwake", "credentials",
        "approvals", "modelScopes", "sessionEncryption", "sessionCompression", "sessionPassword", "taskScope",
        "codemode", "hooks", "threads", "agents", "sandbox", "ui", "skills", "presets", "mcp", "environment", "openers",
        "jobs", "policy"
    ]

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
        for key in container.allKeys { try body(key, container) }
    }

    private struct Decoded: Decodable {
        var file = ConfigurationFile()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                if let setting = ConfigurationFile.settings.named[key.stringValue] {
                    return try setting.read(&file, container, key, key.stringValue)
                }
                guard let section = ConfigurationFile.sections[key.stringValue] else {
                    throw UnknownKey(key: key.stringValue)
                }
                try section.read(&file, container, key)
            }
        }
    }
}
