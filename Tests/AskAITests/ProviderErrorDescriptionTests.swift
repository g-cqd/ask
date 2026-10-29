internal import Testing

@testable import AskAI

/// What a person reads when a provider fails: a sentence, not a Swift value dump (diary 14 printed
/// `status(400, Optional(AskAI.ProviderFailure(kind: …`).
@Suite("Provider errors read as sentences")
struct ProviderErrorDescriptionTests {
    @Test func `a refusal names the status and the provider's own words`() {
        let error = OpenAICompatibleError.status(
            400,
            ProviderFailure(
                kind: .contextOverflow, message: "request (10392 tokens) exceeds the available context size"))
        #expect(
            "\(error)"
                == "the provider refused the request (HTTP 400): request (10392 tokens) exceeds the available context size"
        )
    }

    @Test func `a refusal without a reason still says what happened`() {
        #expect("\(AnthropicClientError.status(502, nil))" == "the provider answered HTTP 502")
    }

    @Test(arguments: [
        (AnthropicClientError.truncated, "the connection closed in the middle of the response"),
        (.transport("offline"), "the request did not complete: offline"),
        (
            .interrupted("no data arrived for 600 seconds"),
            "the connection failed during the response: no data arrived for 600 seconds"
        ),
        (.framing(.eventTooLarge(limit: 8)), "the response stream sent an event larger than 8 bytes")
    ])
    func `other failures say what happened`(error: AnthropicClientError, text: String) {
        #expect("\(error)" == text)
    }

    @Test func `a failure inside the stream says so, with the provider's words`() {
        let error = OpenAICompatibleError.stream(.provider(ProviderFailure(kind: .server, message: "model crashed")))
        #expect("\(error)" == "the provider reported a failure: model crashed")
    }
}
