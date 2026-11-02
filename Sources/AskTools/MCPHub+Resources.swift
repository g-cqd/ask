internal import AskAgentCore
internal import AskMCP
internal import Synchronization

/// A server's resources for the person (roadmap 0067): listed for the `@server:` picker, and read for each `@server:uri` of a message.
extension MCPHub {
    /// The connected servers that have resources, in name order.
    // @dl:accept -- two listings of one server through one helper: each line names its own request and fields
    public var resourceServers: [String] { state.withLock { $0.host?.resources.names } ?? [] }

    /// The resources `server` lists, as the picker shows them: its URI and its name; nil when it is not a connected server with resources
    /// or the listing failed.
    public func listedResources(of server: String) async -> [(uri: String, name: String)]? {
        await listing(server) { try await $0.listResources().map { (uri: $0.uri, name: $0.title ?? $0.name) } }
    }

    /// The resource templates `server` lists (`apple-docs://doc/{+key}`), for the `@server:` picker; nil as for its resources.
    public func listedTemplates(of server: String) async -> [(template: String, name: String)]? {
        await listing(server) { try await $0.listResourceTemplates().map { (template: $0.uriTemplate, name: $0.name) } }
    }

    /// What `list` reads from `server`'s connection; nil when it is not a connected server with resources or the read failed.
    private func listing<Row>(_ server: String, _ list: (MCPConnection) async throws -> [Row]) async -> [Row]? {
        guard let connection = state.withLock({ $0.host?.resources.connection(server) }) else { return nil }
        return try? await list(connection)
    }

    /// What of `template` is written for the person to finish: the URI up to its first variable (RFC 6570's `{`).
    public static func typedPart(of template: String) -> String {
        String(template.prefix { $0 != "{" })
    }

    /// `text` with what each of its `@server:uri` reads attached after it, or why one could not be read.
    public func attachResources(_ text: String) async -> String {
        guard text.contains("@") else { return text }
        let references = ResourceReferences.words(text, servers: Set(resourceServers))
        guard !references.isEmpty else { return text }
        var read: [(ResourceReference, String)] = []
        for reference in references { read.append((reference, await body(of: reference))) }
        return ResourceReferences.attach(text, read)
    }

    /// Subscribes to a resource a message attached, once, where its server can, so a change is told (the owner's choice, 2026-11-02). A
    /// refused subscription changes nothing for the message.
    private func follow(_ reference: ResourceReference) async {
        guard let host = state.withLock({ $0.host }),
            let connection = host.resources.follow(reference.server, reference.uri)
        else {
            return
        }
        try? await connection.subscribe(to: reference.uri)
    }

    /// What a message carries of a resource: its text parts, and the others named.
    private func body(of reference: ResourceReference) async -> String {
        guard let connection = state.withLock({ $0.host?.resources.connection(reference.server) }) else {
            return "[not read: \(reference.server) is not connected]"
        }
        do {
            let parts = try await connection.readResource(reference.uri)
            await follow(reference)
            guard !parts.isEmpty else { return "[the server returned nothing for it]" }
            return
                parts.map { part in
                    switch part.body {
                        case .text(let text): text
                        case .blob: "[\(part.uri)\(part.mimeType.map { " (\($0))" } ?? ""): not text, not attached]"
                    }
                }
                .joined(separator: "\n")
        } catch {
            return "[not read: \(MCPFailure.describe(error, server: reference.server))]"
        }
    }
}
