internal import Foundation

extension ResponsesClient {
    /// The ChatGPT subscription's Codex backend, as the Codex CLI addresses it: the account and the session in headers,
    /// the access token as a bearer, no output limit, a prompt cache keyed by the session, instructions always sent, and the
    /// reasoning it sealed earlier in the tool loop sent back (probed live, ADR-0061).
    ///
    /// Taken from pi's Codex streamer and observed against the live service (diary 27, ADR-0061).
    /// - Parameters:
    ///   - transport: what sends the requests.
    ///   - credentials: the signed-in account's current credentials.
    ///   - session: an identifier for this run, shared by every request in it.
    ///   - replay: remembers a refusal of replayed reasoning for the run.
    /// - Returns: a client for that backend.
    public static func codex(
        transport: any HTTPTransport, credentials: CodexCredentials, session: String,
        replay: ReasoningReplayGate? = nil
    ) -> ResponsesClient {
        ResponsesClient(
            transport: transport, baseURL: URL(string: "https://chatgpt.com/backend-api/codex")!,
            apiKey: credentials.accessToken,
            headers: [
                "chatgpt-account-id": credentials.accountID, "originator": CodexOAuth.originator,
                "OpenAI-Beta": "responses=experimental", "session-id": session, "x-client-request-id": session
            ],
            dialect: ResponsesDialect(
                sendsOutputLimit: false, promptCacheKey: session, fallbackInstructions: "You are a helpful assistant.",
                replaysReasoning: true),
            replay: replay)
    }
}
