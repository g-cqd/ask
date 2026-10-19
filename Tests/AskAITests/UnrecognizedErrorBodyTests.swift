internal import Testing

@testable import AskAI

/// Error bodies that are not OpenAI's `{"error":{…}}` still yield the provider's own sentence and a kind from the
/// HTTP status. Every body here is what the provider answered to an unauthenticated request (diary 14).
@Suite("Every provider's error body yields a readable reason")
struct UnrecognizedErrorBodyTests {
    static let bodies: [(provider: String, status: Int, body: String, message: String, kind: ProviderFailure.Kind)] = [
        ("Mistral", 401, #"{"detail":"Invalid API Key"}"#, "Invalid API Key", .authentication),
        (
            "xAI", 401, #"{"code":"unauthenticated:no-credentials","error":"No credentials presented."}"#,
            "No credentials presented.", .authentication
        ),
        ("DeepSeek", 401, "Authentication Fails (governor)", "Authentication Fails (governor)", .authentication),
        ("Together", 401, "Missing API key", "Missing API key", .authentication),
        ("Cerebras", 403, #"{"detail":"Not authenticated"}"#, "Not authenticated", .permission),
        (
            "Gemini", 400,
            #"[{"error":{"code":400,"message":"Missing or invalid Authorization header.","status":"INVALID_ARGUMENT"}}]"#,
            "Missing or invalid Authorization header.", .invalidRequest
        )
    ]

    @Test(arguments: UnrecognizedErrorBodyTests.bodies)
    func `the reason is the provider's sentence and the kind comes from the status`(
        provider: String, status: Int, body: String, message: String, kind: ProviderFailure.Kind
    ) {
        let failure = ProviderFailure(unrecognizedBody: Array(body.utf8), status: status)
        #expect(failure?.message == message, "\(provider)")
        #expect(failure?.kind == kind, "\(provider)")
    }

    @Test func `an empty body yields nothing, and a huge one is cut`() {
        #expect(ProviderFailure(unrecognizedBody: [], status: 500) == nil)
        #expect(ProviderFailure(unrecognizedBody: Array("<html>bad gateway</html>".utf8), status: 502) == nil)
        let long = String(repeating: "x", count: 5_000)
        #expect((ProviderFailure(unrecognizedBody: Array(long.utf8), status: 500)?.message.count ?? 0) <= 301)
    }

    @Test func `the client reports such a body in the provider's words`() {
        let error = OpenAICompatibleError.status(
            401, ProviderFailure(unrecognizedBody: Array("Missing API key".utf8), status: 401))
        #expect("\(error)" == "the provider refused the request (HTTP 401): Missing API key")
    }
}
