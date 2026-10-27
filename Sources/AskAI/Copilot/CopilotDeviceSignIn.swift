public import Foundation

/// GitHub device approval with only user:email scope; no editor credential-store access.
public struct CopilotDeviceSignIn: BrowserSignIn {
    public struct Device: Sendable { let code: String }
    public let pollsImmediately = false
    // @dl:accept -- device flows carry an HTTP client and injected wall clock; the requests and grants differ
    private let http: CopilotHTTP
    private let now: @Sendable () -> Double

    public init(transport: any HTTPTransport, now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 })
    {
        http = CopilotHTTP(transport: transport)
        self.now = now
    }

    public func start() async throws(SignInError) -> SignInStart<Device> {
        let begun = try await http.form(
            "login/device/code", values: [("client_id", CopilotProtocol.clientID), ("scope", "user:email")],
            as: Begun.self)
        guard SignInSecret.isValid(begun.device_code), SignInSecret.isValid(begun.user_code),
            (1 ... 3600).contains(begun.expires_in), (1 ... begun.expires_in).contains(begun.interval),
            begun.verification_uri == "https://github.com/login/device"
        else { throw .invalidResponse("GitHub device response") }
        return SignInStart(
            session: Device(code: begun.device_code), url: URL(string: begun.verification_uri)!,
            window: .seconds(begun.expires_in), interval: .seconds(begun.interval),
            instructions: "Enter this code there: \(begun.user_code)")
    }

    public func poll(_ session: Device) async throws(SignInError) -> SignInPoll<String> {
        let result = try await http.form(
            "login/oauth/access_token",
            values: [
                ("client_id", CopilotProtocol.clientID), ("device_code", session.code),
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
            ], as: GrantBody.self)
        if let token = result.access_token, SignInSecret.isValid(token) { return .complete(token) }
        switch result.error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            default: throw .invalidResponse("GitHub device approval declined or expired; restart /login")
        }
    }

    public func finish(_ session: Device, grant: String) async throws(SignInError) -> CopilotCredentials {
        try await CopilotAuthClient(transport: http.transport)
            .exchange(
                githubToken: grant, machineID: UUID().uuidString, deviceID: UUID().uuidString, now: now())
    }

    private struct Begun: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let interval: Int
        let expires_in: Int
    }
    private struct GrantBody: Decodable {
        let access_token: String?
        let error: String?
    }
}
