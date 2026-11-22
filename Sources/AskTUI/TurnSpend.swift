/// What the last turn cost, for the status line until the next turn (roadmap 0239): its requests, tool calls and tokens, and how long it
/// took, the tools' share apart. A figure that is not known (a provider that did not count, a session an older ask wrote) is nil.
public struct TurnSpend: Sendable, Equatable {
    public var requests: Int
    public var toolCalls: Int
    /// The tokens as the status line says them, `↑45k ↓3.1k`; nil when none were counted.
    public var tokens: String?
    public var seconds: Int64?
    public var toolSeconds: Int64?

    // @dl:accept -- a memberwise initialiser reads like any other of its kind; the fields are the data
    public init(requests: Int, toolCalls: Int, tokens: String?, seconds: Int64?, toolSeconds: Int64?) {
        self.requests = requests
        self.toolCalls = toolCalls
        self.tokens = tokens
        self.seconds = seconds
        self.toolSeconds = toolSeconds
    }

    /// The whole of it, as a done task's line says it too: `4 requests, 6 tools · ↑45k ↓3.1k · 1:12, tools 0:30`, a figure not known
    /// left out.
    public func summary(localized: Bool) -> String {
        let say = { (seconds: Int64) in
            localized ? DurationText.localized(seconds) : DurationText.clock(seconds, minutes: true)
        }
        let counts =
            "\(requests) request\(requests == 1 ? "" : "s")"
            + (toolCalls == 0 ? "" : ", \(toolCalls) tool\(toolCalls == 1 ? "" : "s")")
        let tools = toolSeconds.flatMap { $0 > 0 && toolCalls > 0 ? ", tools " + say($0) : nil } ?? ""
        return [counts, tokens, seconds.map { say($0) + tools }].compactMap(\.self).joined(separator: " · ")
    }

    /// The segment's forms, longest first: `last turn 4 requests, 6 tools · ↑45k ↓3.1k · 1:12, tools 0:30`, then
    /// `turn ↑45k ↓3.1k · 1:12`, then `turn 1:12`.
    func forms(localized: Bool) -> [String] {
        let time = seconds.map { localized ? DurationText.localized($0) : DurationText.clock($0, minutes: true) }
        let middle = (["turn"] + [tokens, time].compactMap(\.self)).joined(separator: " ")
        return ["last turn " + summary(localized: localized), middle] + (time.map { ["turn " + $0] } ?? [])
    }
}
