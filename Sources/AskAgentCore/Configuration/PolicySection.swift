/// `policy`: what only an organisation decides (roadmap 0130, ADR-0168), set in its `requirements.json` and nowhere else. Every key is
/// optional; unset allows. Between the organisation's documents, a later one replaces what an earlier one set.
public struct PolicySection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `policy.allowNoSandbox`: whether `--no-sandbox` and `--yolo` may turn the sandbox off.
    public var allowNoSandbox: Bool?
    /// `policy.allowYes`: whether `--yes` and `--yolo` may run every tool call without asking.
    public var allowYes: Bool?
    /// `policy.providers`: the connections ask may use, by the name `/model` takes; `*` in a name matches anything.
    public var providers: [String]?
    /// `policy.models`: the models ask may use, by id; `*` in a name matches anything.
    public var models: [String]?
    /// `policy.mcpServers`: the MCP servers ask may start or reach, by what they are, not the name a person gives them: a server's
    /// URL, or its command and arguments separated by blanks; `*` matches anything. A server none matches is switched off.
    public var mcpServers: [String]?
    /// `policy.managedHooksOnly`: whether only the organisation's documents may set a hook command; one set anywhere else is off.
    public var managedHooksOnly: Bool?
    /// `policy.managedSkillsOnly`: whether skills come only from the organisation's folder (`skills` beside its requirements),
    /// which must belong to root as its documents do.
    public var managedSkillsOnly: Bool?
    /// `policy.gatewayAllowed`: whether this computer may share its sessions with a gateway (ADR-0170).
    public var gatewayAllowed: Bool?
    /// `policy.gatewayApprovals`: whether a controller through the gateway may answer approvals.
    public var gatewayApprovals: Bool?
    /// `policy.gatewayStart`: whether a controller through the gateway may start sessions.
    public var gatewayStart: Bool?

    /// The keys, in the order they are shown, from their declarations (``PolicySection/settings``).
    public static let keys = settings.all.map(\.name)

    public var description: String { Self.settings.describe(self) }

    /// What this policy does not allow of a run that turns the sandbox off (`noSandbox`), runs every call without asking (`yes`), and
    /// uses `model` on the connection `provider`; nil when it allows all of it.
    public func refusal(noSandbox: Bool, yes: Bool, provider: String, model: String) -> String? {
        if noSandbox, allowNoSandbox == false { return "turning the sandbox off (--no-sandbox, --yolo)" }
        if yes, allowYes == false { return "running every tool call without asking (--yes, --yolo)" }
        if !Self.allows(providers, provider) {
            return "the connection \(provider); it allows \(providers?.joined(separator: ", ") ?? "")"
        }
        if !Self.allows(models, model) {
            return "the model \(model); it allows \(models?.joined(separator: ", ") ?? "")"
        }
        return nil
    }

    /// Whether the organisation lets ask use `server`: always without a list, else when one entry matches what it is.
    public func permits(_ server: MCPServerSetting) -> Bool {
        Self.allows(mcpServers, Self.identity(of: server))
    }

    /// What a server is, for the allowlist: its URL, else its command and arguments separated by blanks.
    static func identity(of server: MCPServerSetting) -> String {
        server.url ?? ([server.command ?? ""] + server.args).joined(separator: " ")
    }

    /// Whether `name` is allowed by `list`: always when there is no list, else when one entry matches it, `*` matching any run of
    /// characters.
    public static func allows(_ list: [String]?, _ name: String) -> Bool {
        guard let list else { return true }
        return list.contains { matches($0[...], name[...]) }
    }

    private static func matches(_ pattern: Substring, _ name: Substring) -> Bool {
        guard let first = pattern.first else { return name.isEmpty }
        guard first == "*" else { return name.first == first && matches(pattern.dropFirst(), name.dropFirst()) }
        let rest = pattern.dropFirst()
        var tail = name
        while true {
            if matches(rest, tail) { return true }
            guard !tail.isEmpty else { return false }
            tail = tail.dropFirst()
        }
    }
}
