/// The GitHub grant is used only for token exchange; inference receives only the short-lived Copilot token.
public struct CopilotCredentials: Codable, Sendable, Equatable {
    public let githubToken: String
    public let accessToken: String
    public let expiresAt: Double
    public let apiURL: String
    public let machineID: String
    public let deviceID: String

    public init(
        githubToken: String, accessToken: String, expiresAt: Double, apiURL: String, machineID: String, deviceID: String
    ) {
        self.githubToken = githubToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.apiURL = apiURL
        self.machineID = machineID
        self.deviceID = deviceID
    }

    func validated() throws(SignInError) -> CopilotCredentials {
        guard [githubToken, accessToken, machineID, deviceID].allSatisfy({ SignInSecret.isValid($0) }),
            expiresAt.isFinite
        else { throw .invalidResponse("Copilot credentials") }
        _ = try CopilotProtocol.endpoint(apiURL)
        return self
    }
}
