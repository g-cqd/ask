internal import AskAI
internal import Foundation
internal import Synchronization

/// What `ask -p` prints (roadmap 0028): the answer to standard output, tool activity and diagnostics to standard error, with
/// `out` and `err` injectable so the behaviour can be tested.
public final class PrintRenderer: Sendable {
    private let midLine = Mutex(false)
    private let usage = Mutex(UsageTotals())
    private let out: @Sendable (String) -> Void
    private let err: @Sendable (String) -> Void

    /// A renderer writing to the standard handles.
    public init() {
        out = { @Sendable (text: String) in FileHandle.standardOutput.write(Data(text.utf8)) }
        err = { @Sendable (text: String) in FileHandle.standardError.write(Data(text.utf8)) }
    }

    /// A renderer writing wherever `out` and `err` say.
    /// - Parameters:
    ///   - out: where the answer goes.
    ///   - err: where tool activity and diagnostics go.
    public init(out: @escaping @Sendable (String) -> Void, err: @escaping @Sendable (String) -> Void) {
        self.out = out
        self.err = err
    }

    /// Token usage over the run, for the closing line.
    public var usageSummary: String { usage.withLock { $0.summary } }

    /// Prints one event of the run.
    public func render(_ event: AgentEvent) {
        if let spent = event.usage { usage.withLock { $0.add(spent) } }
        if let notice = RunNotices.compaction(for: event) {
            endLine()
            err("ask: \(notice)\n")
        }
        switch event {
            case .model(.textDelta(_, let text)):
                out(text)
                midLine.withLock { $0 = !text.hasSuffix("\n") }
            case .toolStarted(_, let name, let input):
                endLine()
                let shown = String(decoding: input.bytes, as: UTF8.self)
                err("▸ \(name) \(shown.count > 200 ? String(shown.prefix(200)) + "…" : shown)\n")
            case .toolFinished(_, _, let output):
                let first = output.content.split(separator: "\n").last.map(String.init) ?? ""
                err(output.isError ? "  ✗ \(first)\n" : "  ✓\n")
            case .model(.notice(let text)):
                endLine()
                err("ask: \(text)\n")
            case .repaired(let repairs):
                err("ask: repaired the context: \(RequestContext.describe(repairs)).\n")
            case .continuedAtOutputLimit:
                endLine()
                err("ask: the response hit the output limit; asking the model to continue.\n")
            case .retrying(let attempt, let total, let delay, let reason):
                endLine()
                err("ask: \(RunNotices.retry(attempt: attempt, of: total, delay: delay, reason: reason))\n")
            case .finished:
                endLine()
            default:
                break
        }
    }

    /// Finishes a half-written line of the answer before anything else is said.
    private func endLine() {
        if midLine.withLock({ $0 }) { out("\n") }
        midLine.withLock { $0 = false }
    }
}
