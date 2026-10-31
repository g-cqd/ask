internal import AemiJSON

extension AnthropicRequestEncoder {
    /// Clients validate protocol compatibility before entering the serializer. Nil writes no bytes, preserving the
    /// pre-setting payload. No managed-effort beta or system-message marker is needed for the live probed requests.
    ///
    /// Adaptive and budgeted thinking ask for `display: "summarized"`: from Opus 4.7 on the default is `"omitted"`, which streams the
    /// thinking empty. The off modes take no display (`between_tools` takes no other field at all).
    static func encodeThinking(_ control: ThinkingControl?, into writer: inout JSONStreamWriter) {
        guard let control else { return }
        let mode: String
        var budget: Int?
        var effort: ThinkingLevel?
        switch control {
            case .disabled: mode = "disabled"
            case .betweenTools: mode = "between_tools"
            case .adaptive: mode = "adaptive"
            case .effort(let level):
                mode = "adaptive"
                effort = level
            case .budget(let tokens, let level):
                mode = "enabled"
                budget = tokens
                effort = level
        }
        writer.key("thinking")
        writer.object { writer in
            writer.field("type", mode)
            if let budget { writer.field("budget_tokens", budget) }
            if mode == "adaptive" || mode == "enabled" { writer.field("display", "summarized") }
        }
        if let effort {
            writer.key("output_config")
            writer.object { $0.field("effort", effort.rawValue) }
        }
    }
}
