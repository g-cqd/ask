internal import Foundation
internal import Synchronization

/// Why a request did not complete.
public enum HTTPTransportError: Error, Sendable, Equatable {
    /// The connection failed before a response arrived, with the system's description.
    case failed(String)
    case bodyTooLarge(limit: Int)
}
