internal import AemiJSON
public import Foundation

/// Mistral Vibe's browser sign-in (from pi-integrations' `mistral-vibe/provider.ts`, itself from Mistral's public Vibe
/// source): a PKCE-bound process, browser approval, polling for an exchange token, and a PKCE exchange for an API key.
///
/// The key is a Mistral API key, not an OAuth token pair: nothing refreshes, and it is revoked in Mistral's console.
public struct VibeSignIn: KeySignIn {
    /// The name the key is stored under: it is a Mistral key, so Mistral's preset finds it.
    public static let provider = "mistral"

    public let pollsImmediately = true

    private struct Begun: Decodable {
        let process_id: String?
        let sign_in_url: String?
        let poll_url: String?
        let expires_at: String?
    }
    private struct Polled: Decodable {
        let status: String?
        let exchange_token: String?
    }
    private struct Exchanged: Decodable { let api_key: String? }

    private static let console = URL(string: "https://console.mistral.ai")!
    private static let api = URL(string: "https://console.mistral.ai/api")!
    private static let longest = Duration.seconds(600)

    private let http: SignInHTTP
    private let pkce: PKCE
    private let now: @Sendable () -> Double

    /// A sign-in over `transport`. `pkce` is fresh for every attempt unless a test fixes it.
    public init(
        transport: any HTTPTransport, pkce: PKCE = .generate(),
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) {
        http = SignInHTTP(transport: transport)
        self.pkce = pkce
        self.now = now
    }

    public func start() async throws(SignInError) -> SignInStart<VibeSession> {
        let body = JSONStreamWriter.object(of: [("code_challenge", pkce.challenge), ("code_challenge_method", "S256")])
        let begun = try await http.post(Self.api.appending(path: "vibe/sign-in"), json: body).succeeded()
            .decode(Begun.self)
        guard let id = begun.process_id, PlainToken.matches(id, length: 1 ... 200, extra: "_-") else {
            throw .invalidResponse("process_id")
        }
        let link = try SignInURL.trusted(begun.sign_in_url, under: Self.console, field: "sign_in_url")
        let poll = try SignInURL.trusted(begun.poll_url, under: Self.api, field: "poll_url")
        guard let expiry = begun.expires_at.flatMap(Self.seconds(since1970:)), expiry > now() else {
            throw .invalidResponse("expires_at")
        }
        let window = min(Self.longest, .seconds(expiry - now()))
        return SignInStart(
            session: VibeSession(processID: id, pollURL: poll, verifier: pkce.verifier), url: link, window: window,
            interval: .seconds(3))
    }

    public func poll(_ session: VibeSession) async throws(SignInError) -> SignInPoll<String> {
        let reply = try await http.get(session.pollURL)
        if reply.status == 410 { throw .expired }
        let polled = try reply.succeeded().decode(Polled.self)
        return try .reading(
            status: polled.status, secret: polled.exchange_token, complete: "completed", secretField: "exchange_token",
            ending: ["denied": .denied, "expired": .expired])
    }

    public func finish(_ session: VibeSession, grant token: String) async throws(SignInError) -> StoredKey {
        let body = JSONStreamWriter.object(of: [("exchange_token", token), ("code_verifier", session.verifier)])
        let exchanged =
            try await http.post(
                Self.api.appending(path: "vibe/sign-in/\(session.processID)/exchange"), json: body
            )
            .succeeded().decode(Exchanged.self)
        guard SignInSecret.isValid(exchanged.api_key), let key = exchanged.api_key else {
            throw .invalidResponse("api_key")
        }
        return StoredKey(key: key, obtainedAt: now())
    }

    public func timestamp() -> Double { now() }

    private static func seconds(since1970 text: String) -> Double? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)?.timeIntervalSince1970
    }
}
