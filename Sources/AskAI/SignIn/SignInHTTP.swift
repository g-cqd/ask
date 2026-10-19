internal import AemiJSON
internal import Foundation

/// The requests a sign-in makes, and the reading of their answers.
struct SignInHTTP: Sendable {
    /// An answer: its status and body.
    struct Reply: Sendable {
        let status: Int
        let body: [UInt8]

        /// The body as `T`, or ``SignInError/invalidResponse(_:)`` naming `field`.
        func decode<T: Decodable>(_ type: T.Type, field: String = "body") throws(SignInError) -> T {
            do { return try AemiJSON.JSONDecoder().decode(type, from: body) } catch { throw .invalidResponse(field) }
        }

        /// This reply, unless the server refused.
        func succeeded() throws(SignInError) -> Reply {
            guard (200 ..< 300).contains(status) else { throw .rejected(status: status) }
            return self
        }
    }

    /// The most a sign-in answer may weigh: they are a few hundred bytes.
    private static let limit = 64 << 10

    let transport: any HTTPTransport

    func get(_ url: URL) async throws(SignInError) -> Reply { try await send(url, method: "GET", body: []) }

    func post(_ url: URL, json body: [UInt8]) async throws(SignInError) -> Reply {
        try await send(url, method: "POST", body: body)
    }

    private func send(_ url: URL, method: String, body: [UInt8]) async throws(SignInError) -> Reply {
        let request = HTTPRequest(
            url: url, method: method,
            headers: [("content-type", "application/json"), ("accept", "application/json"), ("user-agent", "ask")],
            body: body)
        do {
            let reply = try await transport.send(request)
            return Reply(status: reply.status, body: try await reply.collect(limit: Self.limit))
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport(String(describing: error))
        }
    }
}
