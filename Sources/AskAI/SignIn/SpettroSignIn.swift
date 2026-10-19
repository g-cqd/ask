internal import AemiJSON
public import Foundation

/// Spettro's device sign-in (from pi-integrations' `spettro/provider.ts`): a session id the client invents, a browser
/// link, then polling that session for the device's API key.
///
/// The key is Spettro's own and does not expire on a schedule; it is revoked at spettro.app.
public struct SpettroSignIn: BrowserSignIn {
    /// Where Spettro serves its API unless `SPETTRO_API_URL` says otherwise.
    public static let defaultBase = "https://api.spettro.app"
    /// The name its key is stored under.
    public static let provider = "spettro"

    public let pollInterval = Duration.seconds(2)
    public let pollsImmediately = false

    private struct Initiated: Decodable { let browser_url: String? }
    private struct Polled: Decodable {
        let status: String?
        let api_key: String?
    }

    private let http: SignInHTTP
    private let base: URL
    private let sessionID: String
    private let now: @Sendable () -> Double

    /// A sign-in against `base`, with a session named `sessionID`.
    /// - Throws: ``SignInError/untrustedURL(_:)`` when `base` is not `https`, or `http` to this machine.
    public init(
        transport: any HTTPTransport, base: String = defaultBase, sessionID: String = UUID().uuidString,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) throws(SignInError) {
        http = SignInHTTP(transport: transport)
        self.base = try SignInURL.base(base, field: "SPETTRO_API_URL")
        self.sessionID = sessionID
        self.now = now
    }

    public func start() async throws(SignInError) -> SignInStart<String> {
        let reply =
            try await http.post(
                endpoint("auth/initiate"), json: JSONStreamWriter.object(of: [("session_id", sessionID)])
            )
            .succeeded()
        let link = try SignInURL.browser(reply.decode(Initiated.self).browser_url, field: "browser_url")
        return SignInStart(session: sessionID, url: link, window: .seconds(600))
    }

    public func poll(_ session: String) async throws(SignInError) -> SignInPoll {
        // @dl:accept -- each flow states its own words for the one reading; the shared logic is in SignInPoll.reading
        let reply = try await http.get(endpoint("auth/poll/\(session)"))
        if reply.status == 404 { throw .expired }
        let polled = try reply.succeeded().decode(Polled.self)
        return try .reading(
            status: polled.status, secret: polled.api_key, complete: "complete", secretField: "api_key",
            ending: ["expired": .expired])
    }

    public func timestamp() -> Double { now() }

    private func endpoint(_ path: String) -> URL { base.appending(path: path) }
}
