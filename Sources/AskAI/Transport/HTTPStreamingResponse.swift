internal import Foundation
internal import Synchronization

/// A response whose body arrives as it is received.
public struct HTTPStreamingResponse: Sendable {
    public let status: Int
    /// The body, one chunk per network delivery. Ends when the response ends; throws if it is cut.
    public let body: AsyncThrowingStream<[UInt8], any Error>

    /// A response with this status and body.
    public init(status: Int, body: AsyncThrowingStream<[UInt8], any Error>) {
        self.status = status
        self.body = body
    }

    /// The whole body, for small responses such as errors and tokens.
    /// - Parameter limit: the most bytes to accept, so a broken server cannot grow memory without bound.
    /// - Returns: every byte of the body.
    /// - Throws: ``HTTPTransportError/bodyTooLarge(limit:)``, or the error that cut the body.
    public func collect(limit: Int = 1 << 20) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        for try await chunk in body {
            bytes += chunk
            guard bytes.count <= limit else { throw HTTPTransportError.bodyTooLarge(limit: limit) }
        }
        return bytes
    }
}
