internal import Foundation
internal import Testing

@testable import AskAI

/// A whole small answer in one call: its status and body, bounded, with the transport's own failures left to the caller to
/// name.
@Suite("Collecting an answer returns its status and body, bounded")
struct HTTPTransportCollectingTests {
    private let request = HTTPRequest(url: URL(string: "https://example.test/x")!, method: "GET", headers: [], body: [])

    @Test func `the status and the whole body come back`() async throws {
        let transport = SequencedTransport([.json(201, #"{"a":1}"#)])
        let reply = try await transport.collecting(request)
        #expect(reply.status == 201)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"a":1}"#)
    }

    @Test func `a body past the limit is refused, not buffered`() async {
        let transport = SequencedTransport([.json(200, String(repeating: "a", count: 100))])
        await #expect(throws: HTTPTransportError.bodyTooLarge(limit: 10)) {
            _ = try await transport.collecting(request, limit: 10)
        }
    }

    @Test func `a transport failure is the caller's to name`() async {
        let transport = SequencedTransport([.failure(HTTPTransportError.failed("offline"))])
        await #expect(throws: HTTPTransportError.failed("offline")) { _ = try await transport.collecting(request) }
    }
}
