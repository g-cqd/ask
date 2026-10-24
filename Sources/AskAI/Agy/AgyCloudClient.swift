internal import AemiJSON
internal import Foundation

/// Cloud Code onboarding and the model list.
public struct AgyCloudClient: Sendable {
    private let transport: any HTTPTransport
    private let baseURL: URL

    /// A client sending through `transport`.
    public init(transport: any HTTPTransport) {
        self.transport = transport
        baseURL = AgyCloud.baseURL
    }

    /// The account's project and tiers.
    /// - Parameter accessToken: a current access token.
    /// - Returns: the account.
    /// - Throws: ``AgyCloudError`` or the transport's error.
    public func account(accessToken: String) async throws -> AgyAccount {
        struct Metadata: Encodable {
            let ideName = "ask", ideVersion = "0", pluginVersion = "0", platform = AgyCloud.platform
        }
        struct Body: Encodable {
            let metadata = Metadata()
            let mode = "FULL_ELIGIBILITY_CHECK"
        }
        let reply = try await post("/v1internal:loadCodeAssist", Body(), accessToken: accessToken, limit: 1 << 20)
        guard (200 ..< 300).contains(reply.status) else { throw Self.refusal(reply) }
        guard let root = try? AemiJSON.parse(reply.body).root, root.isObject else {
            throw AgyCloudError.invalidResponse
        }
        guard root["cloudaicompanionProject"].exists else {
            throw AgyCloudError.noProject(reasons: Self.reasons(root["ineligibleTiers"]))
        }
        guard let project = root["cloudaicompanionProject"].string, Self.validProject(project) else {
            throw AgyCloudError.invalidResponse
        }
        return AgyAccount(
            projectID: project, currentTierID: Self.tier(root["currentTier"]), paidTierID: Self.tier(root["paidTier"]))
    }

    /// The chat models the account lists.
    /// - Parameters:
    ///   - accessToken: a current access token.
    ///   - project: the project ``account(accessToken:)`` returned.
    /// - Returns: the models and the server's default.
    /// - Throws: a ``ModelCatalogError``, an ``AgyCloudError`` for a bad project, or the transport's error.
    public func models(accessToken: String, project: String) async throws -> AgyModelList {
        guard Self.validProject(project) else { throw AgyCloudError.invalidResponse }
        struct Body: Encodable { let project: String }
        let reply = try await post(
            "/v1internal:fetchAvailableModels", Body(project: project), accessToken: accessToken, limit: 2 << 20)
        guard reply.status == 200 else { throw ModelCatalogError.refused(status: reply.status) }
        return try AgyModelListing.parse(reply.body)
    }

    private func post<Body: Encodable>(_ path: String, _ body: Body, accessToken: String, limit: Int) async throws
        -> (status: Int, body: [UInt8])
    {
        let bytes = try Array(AemiJSON.JSONEncoder().encode(body))
        var request = HTTPRequest.account("POST", URL(string: baseURL.absoluteString + path)!, body: bytes)
        request.headers = request.headers.filter { $0.name != "user-agent" }
        request.headers += [("authorization", "Bearer " + accessToken), ("user-agent", AgyCloud.userAgent)]
        return try await transport.collecting(request, limit: limit)
    }

    private static func refusal(_ reply: (status: Int, body: [UInt8])) -> AgyCloudError {
        let word = (try? AemiJSON.parse(reply.body))?.root["error"]["status"].string
        return .refused(status: reply.status, reason: word.flatMap { validWord($0, upTo: 40) ? $0 : nil })
    }

    private static func reasons(_ tiers: JSON) -> [String] {
        var found: [String] = []
        for tier in tiers.array ?? [] {
            if let code = tier["reasonCode"].string, validWord(code, upTo: 64), !found.contains(code) {
                found.append(code)
            }
        }
        return found
    }

    private static func tier(_ node: JSON) -> String? {
        guard let id = node["id"].string, (1 ... 64).contains(id.utf8.count),
            id.utf8.allSatisfy({ $0.isASCIIAlphanumeric || $0 == 46 || $0 == 45 || $0 == 95 })
        else { return nil }
        return id
    }

    /// Upper-case words with underscores, which is how Google names a status or a reason.
    private static func validWord(_ text: String, upTo limit: Int) -> Bool {
        (3 ... limit).contains(text.utf8.count) && text.utf8.allSatisfy { ($0 >= 65 && $0 <= 90) || $0 == 95 }
    }

    /// A Cloud project id: it starts alphanumeric and has no separators that mean anything in a path or a body.
    private static func validProject(_ id: String) -> Bool {
        guard (1 ... 128).contains(id.utf8.count), let first = id.utf8.first, first.isASCIIAlphanumeric else {
            return false
        }
        return id.utf8.allSatisfy { $0.isASCIIAlphanumeric || [46, 58, 45, 95].contains($0) }
    }
}

extension UInt8 {
    fileprivate var isASCIIAlphanumeric: Bool {
        (self >= 48 && self <= 57) || (self >= 65 && self <= 90) || (self >= 97 && self <= 122)
    }
}
