public import Foundation

/// What discovery found for a server (roadmap 0067): its authorization server's endpoints, the scope to ask for, and the resource the
/// tokens are for (RFC 8707's canonical URI of the server).
public struct MCPOAuthPlan: Sendable, Equatable {
    public let issuer: URL
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    /// Where a client registers itself (RFC 7591); nil when the server takes no registration.
    public let registrationEndpoint: URL?
    /// The scopes to ask for, space-separated; nil to ask for none in particular.
    public let scope: String?
    /// The server's canonical URI, sent as `resource` with every authorization and token request.
    public let resource: String

    public init(
        issuer: URL,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        registrationEndpoint: URL?,
        scope: String?,
        resource: String
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.scope = scope
        self.resource = resource
    }
}
