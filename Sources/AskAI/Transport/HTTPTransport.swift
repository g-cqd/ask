internal import Foundation
internal import Synchronization

/// Sends HTTP requests. Injected, so the provider client is tested without a network.
public protocol HTTPTransport: Sendable {
    /// Sends `request` and returns as soon as the response's status is known.
    /// - Throws: ``HTTPTransportError/failed(_:)`` when no response arrives, or `CancellationError`.
    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse
}
