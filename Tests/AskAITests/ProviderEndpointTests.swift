internal import Foundation
internal import Testing

@testable import AskAI

/// What a provider's request carries: one of each header, with an extra header replacing a default of the same name.
struct ProviderEndpointTests {
    private static let base = URL(string: "https://example.test/v1")!

    private func sent(_ endpoint: (SequencedTransport) -> ProviderEndpoint) async throws -> HTTPRequest {
        let transport = SequencedTransport([.json(200, "")])
        // The empty answer is an unfinished stream; what is under test is the request, not the reading of the answer.
        do { for try await _ in endpoint(transport).stream([1], decoder: OpenAIStreamDecoder.self) {} } catch {}
        return try #require(transport.sent.first)
    }

    private func values(_ name: String, in request: HTTPRequest) -> [String] {
        request.headers.filter { $0.name.lowercased() == name }.map(\.value)
    }

    @Test func `a path is appended to the base, as it always was`() async throws {
        let request = try await sent {
            ProviderEndpoint(transport: $0, baseURL: Self.base, path: "responses", apiKey: "k", headers: [:])
        }
        #expect(request.url.absoluteString == "https://example.test/v1/responses")
        #expect(values("authorization", in: request) == ["Bearer k"] && values("user-agent", in: request) == ["ask"])
    }

    @Test func `an address with a query is used whole`() async throws {
        let whole = URL(string: "https://example.test/v1/x:stream?alt=sse")!
        let request = try await sent { ProviderEndpoint(transport: $0, url: whole, apiKey: nil, headers: [:]) }
        #expect(request.url.absoluteString == "https://example.test/v1/x:stream?alt=sse")
        #expect(values("authorization", in: request).isEmpty)
    }

    @Test func `an extra header replaces a default of the same name, whatever its case`() async throws {
        for name in ["user-agent", "User-Agent", "USER-AGENT"] {
            let request = try await sent {
                ProviderEndpoint(transport: $0, url: Self.base, apiKey: nil, headers: [name: "mine"])
            }
            #expect(values("user-agent", in: request) == ["mine"], "\(name)")
        }
    }

    @Test func `other extra headers are added after the defaults, in name order`() async throws {
        // A dictionary's order differs from run to run, so eight names make "in name order" unlikely to be luck.
        let extras = Dictionary(
            uniqueKeysWithValues: ["x-h", "x-c", "x-a", "x-g", "x-e", "x-b", "x-f", "x-d"].map { ($0, "v") })
        let request = try await sent { ProviderEndpoint(transport: $0, url: Self.base, apiKey: nil, headers: extras) }
        let names = request.headers.map(\.name)
        #expect(names.suffix(8) == ["x-a", "x-b", "x-c", "x-d", "x-e", "x-f", "x-g", "x-h"])
        #expect(names.filter { $0 == "content-type" }.count == 1)
    }
}
