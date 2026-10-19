import AskAI
import Synchronization

@testable import AskAgentCore

/// Answers each request with the next scripted turn, and keeps every request it received.
final class ScriptedProvider: ModelProvider {
    enum Turn {
        case reply(String)
        /// Text that stops with `pause_turn`: the provider asks to be continued.
        case pause(String)
        case call(id: String, name: String, input: String)
        case calls([(String, String, String)])
        case failure
        /// A failure the provider calls transient, optionally with its own requested wait.
        case transient(retryAfter: Duration?)
        /// Some text reaches the screen, then the stream fails transiently.
        case textThenTransient(String)
        /// A failure the provider says will not succeed if retried, such as a refused credential.
        case permanent
        /// Text that stops at the output-token limit.
        case cutOff(String)
        /// A reply whose request the provider says held `prompt` input tokens.
        case sized(String, prompt: Int)
        /// Text that stops because the context window is full.
        case windowFull(String)
        /// The provider refuses the request for being longer than the context window.
        case overflow
        /// The same refusal, naming the window, as llama.cpp's `n_ctx` and every server's wording do.
        case overflowNaming(window: Int)
        /// Reasoning only, stopped at the output limit before any text: a reasoning model out of reply budget.
        case thinkingOnly(String)
        /// Text that stops for length having written far less than the request allowed: the server's context
        /// filled during generation, which llama.cpp reports as `length`, like the output limit.
        case contextExhausted(String, prompt: Int = 1, output: Int = 3)
    }

    struct OverflowFailure: RetryAdvice, CustomStringConvertible {
        var window: Int?
        var reportedContextWindow: Int? { window }
        var isRetryable: Bool { false }
        var retryAfter: Duration? { nil }
        var isContextOverflow: Bool { true }
        var description: String { "request exceeds the available context size" }
    }

    struct TransientFailure: RetryAdvice, CustomStringConvertible {
        let retryAfter: Duration?
        var isRetryable: Bool { true }
        var description: String { "overloaded" }
    }

    struct PermanentFailure: RetryAdvice, CustomStringConvertible {
        var isRetryable: Bool { false }
        var retryAfter: Duration? { nil }
        var description: String { "credential refused" }
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String { "scripted failure" }
    }

    private let turns: Mutex<[Turn]>
    private let received = Mutex<[ModelRequest]>([])

    init(_ turns: [Turn]) { self.turns = Mutex(turns) }

    var requests: [ModelRequest] { received.withLock { $0 } }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        received.withLock { $0.append(request) }
        let turn = turns.withLock { $0.isEmpty ? Turn.failure : $0.removeFirst() }
        let (stream, continuation) = AsyncThrowingStream<ModelEvent, any Error>.makeStream()
        var events: [ModelEvent] = [.messageStarted(id: "m", model: "claude-x", usage: TokenUsage(input: 1))]
        switch turn {
            case .reply(let text):
                events += [
                    .blockStarted(index: 0, .text), .textDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .endTurn, usage: TokenUsage(output: 1))
                ]
            case .pause(let text):
                events += [
                    .blockStarted(index: 0, .text), .textDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .pauseTurn, usage: TokenUsage(output: 1))
                ]
            case .call(let id, let name, let input):
                events += Self.call(index: 0, id: id, name: name, input: input)
                events.append(.messageDelta(stopReason: .toolUse, usage: TokenUsage(output: 1)))
            case .calls(let calls):
                for (index, call) in calls.enumerated() {
                    events += Self.call(index: index, id: call.0, name: call.1, input: call.2)
                }
                events.append(.messageDelta(stopReason: .toolUse, usage: TokenUsage(output: 1)))
            case .failure:
                continuation.finish(throwing: Failure())
                return stream
            case .sized(let text, let prompt):
                events = [.messageStarted(id: "m", model: "claude-x", usage: TokenUsage(input: prompt))]
                events += [
                    .blockStarted(index: 0, .text), .textDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .endTurn, usage: TokenUsage(output: 1))
                ]
            case .windowFull(let text):
                events += [
                    .blockStarted(index: 0, .text), .textDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .contextWindowExceeded, usage: TokenUsage(output: 1))
                ]
            case .cutOff(let text):
                events += [
                    .blockStarted(index: 0, .text), .textDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .maxTokens, usage: TokenUsage(output: request.maxTokens))
                ]
            case .permanent:
                continuation.finish(throwing: PermanentFailure())
            case .overflow:
                continuation.finish(throwing: OverflowFailure())
                return stream
            case .overflowNaming(let window):
                continuation.finish(throwing: OverflowFailure(window: window))
                return stream
            case .contextExhausted(let text, let prompt, let output):
                events = [.messageStarted(id: "m", model: "claude-x", usage: TokenUsage(input: prompt))]
                events += [
                    .blockStarted(index: 0, .text), .textDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .maxTokens, usage: TokenUsage(output: output))
                ]
            case .thinkingOnly(let text):
                events += [
                    .blockStarted(index: 0, .thinking), .thinkingDelta(index: 0, text), .blockStopped(index: 0),
                    .messageDelta(stopReason: .maxTokens, usage: TokenUsage(output: 1))
                ]
            case .transient(let retryAfter):
                continuation.finish(throwing: TransientFailure(retryAfter: retryAfter))
                return stream
            case .textThenTransient(let text):
                for event in events + [.blockStarted(index: 0, .text), .textDelta(index: 0, text)] {
                    continuation.yield(event)
                }
                continuation.finish(throwing: TransientFailure(retryAfter: nil))
                return stream
        }
        for event in events + [.messageStopped] { continuation.yield(event) }
        continuation.finish()
        return stream
    }

    private static func call(index: Int, id: String, name: String, input: String) -> [ModelEvent] {
        [
            .blockStarted(index: index, .toolUse(id: id, name: name)), .toolInputDelta(index: index, input),
            .blockStopped(index: index)
        ]
    }
}
