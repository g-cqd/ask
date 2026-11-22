extension Configuration {
    /// The document of the organisation that requires `key` (ADR-0168), or nil when nothing requires it. `key` is written in full
    /// (`model`, `ui.tint`, `mcp.docs.command`); a required key above it counts, so a required server locks each of its fields.
    public func requirement(of key: String) -> String? {
        var parts = key.split(separator: ".").map(String.init)
        while !parts.isEmpty {
            if let path = requiredKeys[parts.joined(separator: ".")] { return path }
            parts.removeLast()
        }
        return nil
    }

    /// `self` with what `file`, an organisation's requirements at `path`, sets recorded as required.
    func requiring(_ file: ConfigurationFile, from path: String) -> Configuration {
        var next = self
        for key in file.keysSet { next.requiredKeys[key] = path }
        return next
    }

    /// `self` with what the organisation's policy takes away taken away after every layer (its MCP servers, then its hooks), and a
    /// notice for each thing taken.
    func applyingPolicy(organisationCheck: String?) -> (Configuration, [String]) {
        let (permitted, refusedServers) = applyingServerPolicy()
        let (hooked, refusedHook) = permitted.applyingHookPolicy(organisationCheck: organisationCheck)
        return (hooked, refusedServers + refusedHook)
    }

    /// `self` with each MCP server the organisation's `policy.mcpServers` does not list switched off, and a notice for each.
    func applyingServerPolicy() -> (Configuration, [String]) {
        let policy = self.policy
        guard policy.value.mcpServers != nil else { return (self, []) }
        var next = self
        var notices: [String] = []
        next.mcp.value.servers = mcp.value.servers.map { server in
            guard server.enabled, !policy.value.permits(server) else { return server }
            notices.append(
                "MCP server \(server.name) is not allowed by your organisation (\(policy.source)); it is off."
            )
            var off = server
            off.enabled = false
            return off
        }
        return (next, notices)
    }

    /// `self` with a hook command set outside the organisation's documents replaced by theirs, or off, when its
    /// `policy.managedHooksOnly` says only they may set one; and a notice when that changed anything.
    func applyingHookPolicy(organisationCheck: String?) -> (Configuration, [String]) {
        guard policy.value.managedHooksOnly == true, let check = hooks.value.check, check != organisationCheck else {
            return (self, [])
        }
        var next = self
        next.hooks.value.check = organisationCheck
        let instead = organisationCheck == nil ? "it is off" : "the organisation's runs instead"
        return (
            next,
            [
                "The hook hooks.check is set outside your organisation's documents, which they do not allow "
                    + "(policy.managedHooksOnly, \(policy.source)); \(instead)."
            ]
        )
    }
}
