internal import AemiJSON
internal import AskTUI

/// What a command that goes on after its call has ended prints (a `bash` call that yielded): told on the call that started it,
/// as the screen shows it in that call's block.
struct ACPJobOutput {
    /// The call that started the job.
    let call: String
    /// What the client was last told the job had printed.
    private var told: String?

    init(call: String) { self.call = call }

    /// `tool_call_update` for the call: what the job has printed so far, which replaces what the call showed, and how the job
    /// ended once it has; nil when it runs and has printed nothing the client was not told. The call's status is not touched:
    /// it completed when the tool returned to the model.
    mutating func update(for job: JobUpdate) -> JSONValue? {
        let ending = Self.ending(of: job)
        guard ending != nil || job.output != told else { return nil }
        told = job.output
        var text = job.output
        if let ending {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += ending
        }
        return ["sessionUpdate": "tool_call_update", "toolCallId": .string(call), "content": [ACPToolCall.text(text)]]
    }

    /// The line that says how the job ended, as the screen says it under the block; nil while it runs.
    static func ending(of job: JobUpdate) -> String? {
        switch job.status {
            case .running: nil
            case .failed(let reason) where !reason.isEmpty && reason != job.ending:
                "[\(job.label)] \(job.ending): \(reason)"
            default: "[\(job.label)] \(job.ending)"
        }
    }
}
