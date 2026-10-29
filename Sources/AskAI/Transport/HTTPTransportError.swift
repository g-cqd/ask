internal import Foundation
internal import Synchronization

/// Why a request did not complete.
public enum HTTPTransportError: Error, Sendable, Equatable {
    /// The connection failed before a response arrived, with the system's description.
    case failed(String)
    /// The connection failed after the response began, part way through its body, with the system's description.
    case interrupted(String)
    case bodyTooLarge(limit: Int)
}

extension HTTPTransportError: CustomStringConvertible {
    /// The system's sentence, as it is: what fails is said by whoever reports it ("the request did not complete: …").
    public var description: String {
        switch self {
            case .failed(let reason), .interrupted(let reason): reason
            case .bodyTooLarge(let limit): "the response was larger than \(limit) bytes"
        }
    }
}
