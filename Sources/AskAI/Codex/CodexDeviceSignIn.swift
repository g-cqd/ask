internal import AemiJSON
public import Foundation

/// Codex's device-code sign-in, for a machine with no browser to redirect back to (from pi-integrations' working
/// implementation): the server issues a code the user types at a link, ask polls at the pace the server sets, and the
/// grant it hands over is exchanged for credentials.
public struct CodexDeviceSignIn: BrowserSignIn {
    /// What the sign-in keeps between start and poll.
    public struct Device: Sendable, Equatable {
        let id: String
        let userCode: String
    }

    /// What a finished poll hands over: the code, and the PKCE verifier the server chose for it.
    public struct DeviceGrant: Sendable, Equatable {
        let code: String
        let verifier: String
    }

    private static let base = URL(string: "https://auth.openai.com")!
    private static let verification = URL(string: "https://auth.openai.com/codex/device")!
    private static let redirectURI = "https://auth.openai.com/deviceauth/callback"

    public let pollsImmediately = false

    private let http: SignInHTTP
    private let auth: CodexAuthClient
    private let now: @Sendable () -> Double

    /// A sign-in over `transport`.
    public init(transport: any HTTPTransport, now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 })
    {
        http = SignInHTTP(transport: transport)
        auth = CodexAuthClient(transport: transport)
        self.now = now
    }

    public func start() async throws(SignInError) -> SignInStart<Device> {
        // @dl:accept -- every flow's start is one POST, a decode and a few checks on ids; the endpoints and rules are each its own
        let body = JSONStreamWriter.object(of: [("client_id", CodexOAuth.clientID)])
        let begun = try await http.post(Self.base.appending(path: "api/accounts/deviceauth/usercode"), json: body)
            .succeeded().decode(Begun.self)
        guard let id = begun.device_auth_id, PlainToken.matches(id, length: 1 ... 256, extra: ".:_-"),
            let code = begun.user_code, PlainToken.matches(code, length: 3 ... 64, extra: "-"),
            let seconds = begun.interval?.seconds, seconds.isFinite, seconds >= 0
        else { throw .invalidResponse("device") }
        return SignInStart(
            session: Device(id: id, userCode: code), url: Self.verification, window: .seconds(900),
            interval: .seconds(Swift.min(60, Swift.max(1, seconds))), instructions: "Enter this code there: \(code)")
    }

    public func poll(_ session: Device) async throws(SignInError) -> SignInPoll<DeviceGrant> {
        let body = JSONStreamWriter.object(of: [("device_auth_id", session.id), ("user_code", session.userCode)])
        let reply = try await http.post(Self.base.appending(path: "api/accounts/deviceauth/token"), json: body)
        if (200 ..< 300).contains(reply.status) {
            let grant = try? AemiJSON.JSONDecoder().decode(GrantBody.self, from: reply.body)
            guard SignInSecret.isValid(grant?.authorization_code), SignInSecret.isValid(grant?.code_verifier),
                let code = grant?.authorization_code, let verifier = grant?.code_verifier
            else { throw .invalidResponse("grant") }
            return .complete(DeviceGrant(code: code, verifier: verifier))
        }
        // 403 and 404 are how the server says "not approved yet".
        if reply.status == 403 || reply.status == 404 { return .pending }
        switch CodexErrorBody.code(in: reply.body) {
            case "deviceauth_authorization_pending": return .pending
            case "slow_down": return .slowDown
            default: throw .rejected(status: reply.status)
        }
    }

    public func finish(_ session: Device, grant: DeviceGrant) async throws(SignInError) -> CodexCredentials {
        do {
            return try await auth.exchange(
                code: grant.code, verifier: grant.verifier, redirectURI: Self.redirectURI, now: now())
        } catch { throw SignInError(error) }
    }

    private struct Begun: Decodable {
        let device_auth_id: String?
        let user_code: String?
        let interval: Interval?
    }

    private struct GrantBody: Decodable {
        let authorization_code: String?
        let code_verifier: String?
    }

    /// The poll interval, which the server sends as a number or as text.
    private struct Interval: Decodable {
        let seconds: Double?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                seconds = number
            } else {
                seconds = (try? container.decode(String.self))
                    .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            }
        }
    }
}
