internal import AskAI
internal import AskAgentCore
internal import Foundation
internal import Synchronization

/// `ask -p --json` (roadmap 0234): the run's events as JSON lines on standard output, then an `end` line with the session and the
/// tokens used. Standard error keeps ask's own diagnostics.
final class JSONEvents: Sendable {
    private let writer = JSONEventWriter()
    private let usage = Mutex(TokenUsage())

    func write(_ event: AgentEvent) {
        if let spent = event.usage {
            usage.withLock { total in
                total = TokenUsage(
                    input: (total.input ?? 0) + (spent.input ?? 0),
                    output: (total.output ?? 0) + (spent.output ?? 0),
                    cacheRead: (total.cacheRead ?? 0) + (spent.cacheRead ?? 0),
                    cacheCreation: (total.cacheCreation ?? 0) + (spent.cacheCreation ?? 0)
                )
            }
        }
        for line in writer.lines(for: event) { Self.emit(line) }
    }

    func end(session: String) {
        Self.emit(writer.endLine(session: session, usage: usage.withLock { $0 }))
    }

    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
