/// A sign-in to an MCP server (roadmap 0067): which client ask registered as, where the browser came back to, and the tokens. Kept in the
/// credential file under `mcp`, by the server's canonical address; the tokens are secrets (a keychain keeps them out of the file).
public struct MCPServerCredentials: Sendable, Equatable, Codable {
    /// The server's canonical address, the record's key.
    public var server: String
    /// The authorization server that issued the tokens.
    public var issuer: String
    /// Where the tokens are renewed, kept so a refresh needs no discovery (a server may name its metadata only in a refusal).
    public var tokenEndpoint: String
    public var clientID: String
    /// The address registered for the browser's return, kept so the same client is used again.
    public var redirectURI: String
    public var accessToken: String
    /// Empty when the server gave none.
    public var refreshToken: String
    /// When the access token runs out, in seconds since 1970; nil when the server did not say.
    public var expiresAt: Double?

    public init(
        server: String,
        issuer: String,
        tokenEndpoint: String,
        clientID: String,
        redirectURI: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Double?
    ) {
        self.server = server
        self.issuer = issuer
        self.tokenEndpoint = tokenEndpoint
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
