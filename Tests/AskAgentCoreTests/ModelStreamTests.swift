internal import AskAI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskAgentCore

struct ModelStreamTests {
    private struct Refused: Error, Equatable {}

    private func events(_ stream: AsyncThrowingStream<ModelEvent, any Error>) async -> (
        texts: [String], failure: (any Error)?
    ) {
        var texts: [String] = []
        do {
            for try await event in stream { if case .textDelta(_, let text) = event { texts.append(text) } }
        } catch { return (texts, error) }
        return (texts, nil)
    }

    private func source(_ texts: [String], failing: Bool = false) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            for text in texts { continuation.yield(.textDelta(index: 0, text)) }
            failing ? continuation.finish(throwing: Refused()) : continuation.finish()
        }
    }

    @Test func `the prepared stream's events arrive in order after the preparation ran`() async {
        let order = Mutex<[String]>([])
        let result = await events(
            ModelStream.after {
                order.withLock { $0.append("prepared") }
                return source(["a", "b", "c"])
            })
        #expect(result.texts == ["a", "b", "c"] && result.failure == nil)
        #expect(order.withLock { $0 } == ["prepared"])
    }

    @Test func `a failed preparation ends the stream with that failure and forwards nothing`() async {
        let result = await events(ModelStream.after { throw Refused() })
        #expect(result.texts.isEmpty)
        #expect(result.failure as? Refused == Refused())
    }

    @Test func `a failure inside the prepared stream is delivered after its earlier events`() async {
        let result = await events(ModelStream.after { source(["kept"], failing: true) })
        #expect(result.texts == ["kept"])
        #expect(result.failure as? Refused == Refused())
    }

    @Test func `nothing is requested from the prepared stream before preparation returns`() async {
        let started = Mutex(false)
        let stream = ModelStream.after {
            AsyncThrowingStream { continuation in
                started.withLock { $0 = true }
                continuation.finish()
            }
        }
        #expect(started.withLock { $0 } == false, "building the stream must not start the work")
        _ = await events(stream)
        #expect(started.withLock { $0 })
    }
}
