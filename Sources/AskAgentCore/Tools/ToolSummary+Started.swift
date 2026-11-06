public import AskAI
public import Foundation

/// What the screen shows of a tool call as it starts, from its input decoded once (note n47): a resumed session draws every call it
/// holds, and each was decoded five times for the header, the full input, the command's limits and the path.
extension ToolSummary {
    /// The parts of a started call's block.
    public struct Started: Sendable, Equatable {
        public let header: String
        public let fullInput: String
        /// A command's limits, in seconds; nil for any other tool.
        public let limits: Limits?
        /// The file the call names, as the model wrote it.
        public let path: String?

        /// The `timeout_seconds` and `yield_seconds` a command call set.
        public struct Limits: Sendable, Equatable {
            public let timeout: Int?
            public let yield: Int?
        }
    }

    /// The block's parts for `input` to `tool`: what ``header(for:tool:locale:)``, ``fullInput(for:)``, ``commandLimits(for:)`` and
    /// ``path(for:)`` say, from one decoding.
    public static func started(_ input: JSONObject, tool: String, locale: Locale = .current) -> Started {
        let fields = fields(input)
        return Started(
            header: header(fields, input, tool: tool, locale: locale),
            fullInput: fullInput(fields, input),
            limits: fields.flatMap {
                $0.command == nil ? nil : Started.Limits(timeout: $0.timeoutSeconds, yield: $0.yieldSeconds)
            },
            path: fields?.path
        )
    }
}
