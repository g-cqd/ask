internal import AemiJSON
public import AskAI

/// `ask -p --json` (roadmap 0234): each event of a run as one JSON object on a line, `{"v":1,"type":…}`, for scripts, CI and other
/// front ends. Written with AemiJSON's `JSONStreamWriter`; a tool's input is spliced in as the JSON it already is. Events of no use
/// outside the run (signatures, block boundaries, prompt bookkeeping) give no line.
public final class JSONEventWriter: Sendable {
    /// The format's version, in every line; a field added keeps it, a field changed or removed raises it.
    public static let version = 1

    public init() {}

    /// The lines for `event`: none, or one.
    public func lines(for event: AgentEvent) -> [String] {
        var writer = Self.begin(Self.type(of: event) ?? "")
        guard Self.type(of: event) != nil else { return [] }
        Self.fields(of: event, into: &writer)
        writer.endObject()
        return [String(decoding: writer.finish(), as: UTF8.self)]
    }

    /// The last line: the session the run was recorded in, and the tokens it used.
    public func endLine(session: String, usage: TokenUsage) -> String {
        var writer = Self.begin("end")
        writer.key("session")
        writer.string(session)
        Self.usage(usage, into: &writer)
        writer.endObject()
        return String(decoding: writer.finish(), as: UTF8.self)
    }

    private static func begin(_ type: String) -> JSONStreamWriter {
        var writer = JSONStreamWriter()
        writer.beginObject()
        writer.key("v")
        writer.integer(version)
        writer.key("type")
        writer.string(type)
        return writer
    }

    private static func type(of event: AgentEvent) -> String? {
        switch event {
            case .model(.textDelta): "text"
            case .model(.thinkingDelta): "thinking"
            case .model(.notice): "notice"
            case .toolStarted: "tool_call"
            case .toolFinished: "tool_result"
            case .responded: "response"
            case .retrying: "retry"
            case .compacting: "compacting"
            case .compacted: "compacted"
            case .compactionFailed: "compaction_failed"
            case .hookContinued: "hook_continued"
            case .finished: "finished"
            default: nil
        }
    }

    private static func fields(of event: AgentEvent, into writer: inout JSONStreamWriter) {
        switch event {
            case .model(.textDelta(_, let text)), .model(.thinkingDelta(_, let text)), .model(.notice(let text)),
                .compactionFailed(let text), .hookContinued(let text):
                pair("text", text, into: &writer)
            case .toolStarted(let id, let name, let input):
                pair("id", id, into: &writer)
                pair("name", name, into: &writer)
                writer.key("input")
                writer.raw(input.bytes)
            case .toolFinished(let id, let name, let output):
                pair("id", id, into: &writer)
                pair("name", name, into: &writer)
                writer.key("is_error")
                writer.bool(output.isError)
                pair("content", output.content, into: &writer)
            case .responded(let response):
                writer.key("stop_reason")
                writer.stringOrNull(response.stopReason?.wire)
                usage(response.usage, into: &writer)
            case .retrying(let attempt, let total, let delay, let reason):
                writer.key("attempt")
                writer.integer(attempt)
                writer.key("of")
                writer.integer(total)
                writer.key("delay_ms")
                writer.integer(
                    Int(delay.components.seconds * 1000 + delay.components.attoseconds / 1_000_000_000_000_000)
                )
                pair("reason", reason, into: &writer)
            case .compacted(let summary, let spent):
                pair("summary", summary, into: &writer)
                usage(spent, into: &writer)
            case .finished(let reason):
                writer.key("stop_reason")
                writer.stringOrNull(reason?.wire)
            default:
                break
        }
    }

    private static func pair(_ key: String, _ value: String, into writer: inout JSONStreamWriter) {
        writer.key(key)
        writer.string(value)
    }

    private static func usage(_ usage: TokenUsage, into writer: inout JSONStreamWriter) {
        writer.key("usage")
        writer.beginObject()
        for (key, value) in [
            ("input", usage.input), ("output", usage.output), ("cache_read", usage.cacheRead),
            ("cache_creation", usage.cacheCreation)
        ] {
            guard let value else { continue }
            writer.key(key)
            writer.integer(value)
        }
        writer.endObject()
    }
}
