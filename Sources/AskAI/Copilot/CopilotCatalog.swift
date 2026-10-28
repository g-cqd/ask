internal import AemiJSON
public import Foundation

/// Account-scoped native protocols, persisted without credentials. Empty success replaces a revoked catalog.
public struct CopilotCatalog: Sendable {
    public let access: CopilotAccess
    let transport: any HTTPTransport
    let url: URL
    public init(file: CredentialFile, transport: any HTTPTransport) {
        access = CopilotAccess(file: file, transport: transport)
        self.transport = transport
        url = file.url.deletingLastPathComponent().appending(path: "models-copilot-vscode.json")
    }

    public func cached(now: Double) throws -> [CatalogModel]? {
        guard let credential = try access.file.loadCopilot(), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2 << 20 else { throw SignInError.invalidResponse("Copilot catalog cache") }
        let stored = try AemiJSON.JSONDecoder().decode(Stored.self, from: Array(bytes))
        guard stored.machineID == credential.machineID, stored.apiURL == credential.apiURL,
            stored.at.isFinite, now >= stored.at, now - stored.at < 86_400,
            stored.models.allSatisfy({ $0.isValid && Self.paths.contains($0.api ?? "") }),
            Set(stored.models.map(\.id)).count == stored.models.count
        else { return nil }
        return stored.models
    }

    public func models(now: Double, refresh: Bool = false) async throws -> [CatalogModel] {
        if !refresh, let held = try cached(now: now) { return held }
        let credential = try await access.credentials(now: now)
        let request = HTTPRequest(
            url: try CopilotProtocol.endpoint(credential.apiURL).appending(path: "models"), method: "GET",
            headers: CopilotProtocol.headers(credential, session: UUID().uuidString), body: [], allowsRedirects: false)
        let response = try await CopilotHTTP(transport: transport).json(request, as: Payload.self, limit: 2 << 20)
        let models = Self.parse(response.data)
        // Never publish an old account's response after a concurrent sign-in/out.
        guard try access.file.loadCopilot() == credential else {
            throw SignInError.invalidResponse("Copilot account changed during catalog refresh")
        }
        let bytes = try AemiJSON.JSONEncoder()
            .encodeToBytes(Stored(machineID: credential.machineID, apiURL: credential.apiURL, at: now, models: models))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.replace(url, with: bytes)
        return models
    }

    private static let paths = ["/responses", "/v1/messages", "/chat/completions"]
    private static func parse(_ entries: [Entry]) -> [CatalogModel] {
        var seen = Set<String>()
        return entries.compactMap { item in
            guard CatalogModel.validID(item.id), !seen.contains(item.id), item.model_picker_enabled == true,
                item.policy?.state != "disabled", let caps = item.capabilities, caps.type == "chat",
                caps.supports?.tool_calls == true, caps.supports?.streaming == true,
                let api = paths.first(where: { (item.supported_endpoints ?? ["/chat/completions"]).contains($0) })
            else { return nil }
            seen.insert(item.id)
            let support = caps.supports
            let levels = (support?.reasoning_effort ?? []).filter(CatalogModel.validLevel)
            let adaptive = support?.adaptive_thinking == true
            let thinking = support?.thinking == true || adaptive || !levels.isEmpty
            let model = CatalogModel(
                id: item.id,
                contextWindow: positive(caps.limits?.max_context_window_tokens)
                    ?? positive(caps.limits?.max_prompt_tokens),
                maxOutputTokens: positive(caps.limits?.max_output_tokens), reasoningLevels: Array(Set(levels)).sorted(),
                supportsThinking: thinking,
                thinkingModes: adaptive ? [.adaptive, .disabled] : (thinking ? [.enabled, .disabled] : []), api: api,
                acceptsImages: support?.vision)
            return model.isValid ? model : nil
        }
    }
    private static func positive(_ n: Int?) -> Int? { n.flatMap { $0 > 0 ? $0 : nil } }

    private struct Stored: Codable {
        let machineID: String
        let apiURL: String
        let at: Double
        let models: [CatalogModel]
    }
    private struct Payload: Decodable { let data: [Entry] }
    private struct Entry: Decodable {
        struct Policy: Decodable { let state: String? }
        struct Capabilities: Decodable {
            struct Support: Decodable {
                let tool_calls: Bool?
                let streaming: Bool?
                let thinking: Bool?
                let adaptive_thinking: Bool?
                let reasoning_effort: [String]?
                let vision: Bool?
            }
            struct Limits: Decodable {
                let max_context_window_tokens: Int?
                let max_prompt_tokens: Int?
                let max_output_tokens: Int?
            }
            let type: String?
            let supports: Support?
            let limits: Limits?
        }
        let id: String
        let model_picker_enabled: Bool?
        let supported_endpoints: [String]?
        let policy: Policy?
        let capabilities: Capabilities?
    }
}
