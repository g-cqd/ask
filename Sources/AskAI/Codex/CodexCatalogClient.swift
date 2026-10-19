internal import AemiJSON
public import Foundation

/// Reads the account's Codex model list, not a static catalog shared by unrelated accounts.
public struct CodexCatalogClient: Sendable {
    /// The probed, versioned catalog endpoint. It is also part of the cache's authority key.
    public static let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/models?client_version=0.163.0")!
    private let transport: any HTTPTransport

    /// A client sending through `transport`.
    public init(transport: any HTTPTransport) { self.transport = transport }

    /// The listed text models, in the server's priority order.
    /// - Parameter credentials: the account's current credentials, obtained through ``CodexAccess``.
    /// - Returns: a nonempty list of models usable as defaults.
    /// - Throws: a ``ModelCatalogError`` or the transport's error.
    public func models(credentials: CodexCredentials) async throws -> [CatalogModel] {
        // Required by the live endpoint; this is the probed catalog schema version, not ask's user-agent identity.
        var request = HTTPRequest.account("GET", Self.endpoint)
        request.headers += [
            ("authorization", "Bearer " + credentials.accessToken),
            ("chatgpt-account-id", credentials.accountID), ("originator", CodexOAuth.originator)
        ]
        let reply = try await transport.collecting(request, limit: 2 << 20)
        guard reply.status == 200 else { throw ModelCatalogError.refused(status: reply.status) }
        let catalog: Response
        do { catalog = try AemiJSON.JSONDecoder().decode(Response.self, from: reply.body) } catch {
            throw ModelCatalogError.invalidResponse
        }
        var seen = Set<String>()
        let models = catalog.models.enumerated()
            .sorted {
                $0.element.priority == $1.element.priority
                    ? $0.offset < $1.offset : $0.element.priority < $1.element.priority
            }
            .compactMap { entry -> CatalogModel? in
                guard let model = entry.element.model, seen.insert(model.id).inserted else { return nil }
                return model
            }
        guard !models.isEmpty else { throw ModelCatalogError.noModels }
        return models
    }

    private struct Response: Decodable {
        let models: [CodexCatalogEntry]
    }
}
