extension SessionPayload {
    /// Which case this is.
    var kind: SessionEntry.Kind {
        switch self {
            case .destination: .destination
            case .user: .user
            case .assistant: .assistant
            case .response: .response
            case .toolResult: .toolResult
            case .compaction: .compaction
            case .unrecognized: .unrecognized
        }
    }
}
