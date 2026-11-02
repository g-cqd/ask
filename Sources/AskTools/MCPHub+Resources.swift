internal import AskAgentCore
internal import AskMCP
internal import Synchronization

/// A server's resources for the person (roadmap 0067): listed for the `@server:` picker, and read for each `@server:uri` of a message.
extension MCPHub {
    /// The connected servers that have resources, in name order.
    public var resourceServers: [String] { state.withLock { $0.host?.resources.names } ?? [] }

    /// The resources `server` lists, as the picker shows them: its URI and its name; nil when it is not a connected server with resources
    /// or the listing failed.
    public func listedResources(of server: String) async -> [(uri: String, name: String)]? {
        guard let connection = state.withLock({ $0.host?.resources.connection(server) }),
            let listed = try? await connection.listResources()
        else { return nil }
        return listed.map { (uri: $0.uri, name: $0.title ?? $0.name) }
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

    /// What a message carries of a resource: its text parts, and the others named.
    private func body(of reference: ResourceReference) async -> String {
        guard let connection = state.withLock({ $0.host?.resources.connection(reference.server) }) else {
            return "[not read: \(reference.server) is not connected]"
        }
        do {
            let parts = try await connection.readResource(reference.uri)
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
