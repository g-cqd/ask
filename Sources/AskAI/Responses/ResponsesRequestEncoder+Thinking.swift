internal import AemiJSON

extension ResponsesRequestEncoder {
    /// Compatible controls only: the client rejects native budget/between-tools modes before encoding. The requested
    /// effort is not clamped to a provider catalog; a server may still reject an advertised value. Replay is ADR-0033.
    static func encodeThinking(_ control: ThinkingControl?, into writer: inout JSONStreamWriter) {
        guard let control else { return }
        switch control {
            case .disabled:
                writer.key("reasoning")
                writer.object { $0.field("effort", "none") }
            case .effort(let level):
                writer.key("reasoning")
                writer.object {
                    $0.field("effort", level.rawValue)
                    $0.field("summary", "auto")
                }
            case .budget, .betweenTools: break
        }
    }
}
