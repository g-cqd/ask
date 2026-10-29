extension ProviderStreamError: CustomStringConvertible {
    /// A sentence for the person reading it, with the provider's own words where it gave some.
    public var description: String {
        switch self {
            case .status(let code, let failure?, _):
                "the provider refused the request (HTTP \(code)): \(failure.sentence)"
            case .status(let code, nil, _): "the provider answered HTTP \(code)"
            case .stream(let failure):
                failure.providerFailure.map { "the provider reported a failure: \($0.sentence)" }
                    ?? "the response stream broke the protocol: \(failure)"
            case .framing(.eventTooLarge(let limit)):
                "the response stream sent an event larger than \(limit) bytes"
            case .truncated: "the connection closed in the middle of the response"
            case .transport(let reason): "the request did not complete: \(reason)"
            case .interrupted(let reason): "the connection failed during the response: \(reason)"
        }
    }
}
