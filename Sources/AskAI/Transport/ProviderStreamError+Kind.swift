extension ProviderStreamError {
    /// The kind of failure the provider reported, whether it answered with a status or broke the stream; nil for a failure
    /// that came from the connection or the framing.
    var reportedKind: ProviderFailure.Kind? {
        switch self {
            case .status(_, let failure, _): failure?.kind
            case .stream(let failure): failure.providerFailure?.kind
            default: nil
        }
    }

    /// Whether the server refused the request because it could not verify reasoning the request sent back.
    public var rejectsReplayedReasoning: Bool { reportedKind == .rejectedReasoning }
}
