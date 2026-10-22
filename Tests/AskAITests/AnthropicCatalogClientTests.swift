internal import Foundation
internal import Testing

@testable import AskAI

struct AnthropicCatalogClientTests {
    private static let one = #"{"data":[{"id":"a","max_input_tokens":64000}],"has_more":false,"last_id":"a"}"#

    @Test func `the native endpoint is queried with the same subscription headers as messages`() async throws {
        let transport = SequencedTransport([.json(200, Self.one)])
        let result = try await AnthropicCatalogClient(transport: transport)
            .models(auth: .subscription(accessToken: "fixture-token"))
        #expect(result.models == [CatalogModel(id: "a", contextWindow: 64000)])
        #expect(result.complete)
        #expect(result.notices.isEmpty)
        let request = try #require(transport.sent.first)
        #expect(request.method == "GET")
        #expect(request.url.host() == "api.anthropic.com")
        #expect(request.url.path == "/v1/models")
        #expect(request.body.isEmpty)
        #expect(request.headers.contains { $0.name == "authorization" && $0.value == "Bearer fixture-token" })
        #expect(request.headers.contains { $0.name == "anthropic-beta" && $0.value == AnthropicClient.oauthBetas })
        #expect(request.headers.contains { $0.name == "anthropic-version" && $0.value == "2023-06-01" })
    }

    @Test func `an API key is not turned into subscription authorization`() async throws {
        let transport = SequencedTransport([.json(200, Self.one)])
        _ = try await AnthropicCatalogClient(transport: transport).models(auth: .apiKey("fixture-key"))
        let headers = try #require(transport.sent.first).headers
        #expect(headers.contains { $0.name == "x-api-key" && $0.value == "fixture-key" })
        #expect(!headers.contains { $0.name == "authorization" || $0.name == "anthropic-beta" })
    }

    @Test func `every reported page is read with an encoded cursor and duplicate ids are not duplicated`() async throws
    {
        let first = #"{"data":[{"id":"a"}],"has_more":true,"last_id":"a"}"#
        let last = #"{"data":[{"id":"a"},{"id":"b"}],"has_more":false,"last_id":"b"}"#
        let transport = SequencedTransport([.json(200, first), .json(200, last)])
        let result = try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        #expect(result.models.map(\.id) == ["a", "b"])
        #expect(result.complete)
        try #require(transport.sent.count == 2)
        let queries = transport.sent.map {
            URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        }
        #expect(queries[0].contains(URLQueryItem(name: "limit", value: "1000")))
        #expect(!queries[0].contains { $0.name == "after_id" })
        #expect(queries[1].contains(URLQueryItem(name: "after_id", value: "a")))
        #expect(!result.notices.isEmpty, "the repeated descriptor must be said")
    }

    @Test func `a repeating cursor retains every intact model but does not claim a complete download`() async throws {
        let first = #"{"data":[{"id":"a"}],"has_more":true,"last_id":"a"}"#
        let repeated = #"{"data":[{"id":"b"}],"has_more":true,"last_id":"a"}"#
        let transport = SequencedTransport([.json(200, first), .json(200, repeated)])
        let result = try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        #expect(result.models.map(\.id) == ["a", "b"])
        #expect(!result.complete)
        #expect(!result.notices.isEmpty)
        #expect(transport.sent.count == 2)
    }

    @Test(arguments: [
        #"{"data":[{"id":"m"}]}"#, #"{"data":[{"id":"m"}],"has_more":"no"}"#,
        #"{"data":[{"id":"m"}],"has_more":true}"#,
        #"{"data":[{"id":"m"}],"has_more":true,"last_id":"bad cursor"}"#
    ])
    func `broken pagination costs completeness and caching, not intact descriptors`(_ reply: String) async throws {
        let transport = SequencedTransport([.json(200, reply)])
        let result = try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        #expect(result.models.map(\.id) == ["m"])
        #expect(!result.complete)
        #expect(!result.notices.isEmpty)
        #expect(transport.sent.count == 1)
    }

    @Test func `an unending service is bounded by pages without discarding the pages already received`() async throws {
        let replies = (0 ..< AnthropicCatalogClient.maximumPages + 1)
            .map { index in
                SequencedTransport.Reply.json(
                    200, #"{"data":[{"id":"m\#(index)"}],"has_more":true,"last_id":"m\#(index)"}"#)
            }
        let transport = SequencedTransport(replies)
        let result = try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        #expect(result.models.count == AnthropicCatalogClient.maximumPages)
        #expect(!result.complete)
        #expect(transport.sent.count == AnthropicCatalogClient.maximumPages)
        #expect(!result.notices.isEmpty)
    }

    @Test func `a service listing too many models is bounded without losing the first usable ones`() async throws {
        let entries = (0 ..< AnthropicCatalogClient.maximumModels + 1).map { #"{"id":"m\#($0)"}"# }
            .joined(separator: ",")
        let transport = SequencedTransport([.json(200, #"{"data":[\#(entries)],"has_more":false}"#)])
        let result = try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        #expect(result.models.count == AnthropicCatalogClient.maximumModels)
        #expect(!result.complete)
        #expect(!result.notices.isEmpty)
    }

    @Test(arguments: [401, 403, 404, 429, 500])
    func `refusals name only the status`(_ status: Int) async {
        let transport = SequencedTransport([.json(status, "fixture-key must never be shown")])
        await #expect(throws: ModelCatalogError.refused(status: status)) {
            try await AnthropicCatalogClient(transport: transport).models(auth: .apiKey("fixture-key"))
        }
    }

    @Test func `no usable models is an error rather than a false empty catalog`() async {
        let transport = SequencedTransport([.json(200, #"{"data":[],"has_more":false}"#)])
        await #expect(throws: ModelCatalogError.noModels) {
            try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        }
    }

    @Test func `oversized model replies are rejected before parsing`() async {
        let transport = SequencedTransport([.json(200, String(repeating: "x", count: (2 << 20) + 1))])
        await #expect(throws: HTTPTransportError.bodyTooLarge(limit: 2 << 20)) {
            try await AnthropicCatalogClient(transport: transport).models(auth: .bearer("t"))
        }
    }
}
