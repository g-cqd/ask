internal import AskAI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskAgentCore

struct DeferredThinkingProviderTests {
    private struct Refused: Error, Equatable {}

    private func request() -> ModelRequest {
        ModelRequest(model: "m", maxTokens: 4096, systemPrompt: [], messages: [], tools: [])
    }

    private func drain(_ provider: some ModelProvider) async -> (any Error)? {
        do { for try await _ in provider.stream(request()) {} } catch { return error }
        return nil
    }

    @Test func `the first request carries the looked-up control and the lookup runs once for later ones`() async {
        let inner = ScriptedProvider([.reply("a"), .reply("b")])
        let calls = Mutex(0)
        let provider = DeferredThinkingProvider(inner: inner) {
            calls.withLock { $0 += 1 }
            return .effort(.high)
        }
        let first = await drain(provider)
        let second = await drain(provider)
        #expect(first == nil && second == nil)
        #expect(inner.requests.map(\.thinking) == [.effort(.high), .effort(.high)])
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func `no control is a result too, and it is kept rather than looked up again`() async {
        let inner = ScriptedProvider([.reply("a"), .reply("b")])
        let calls = Mutex(0)
        let provider = DeferredThinkingProvider(inner: inner) {
            calls.withLock { $0 += 1 }
            return nil
        }
        _ = await drain(provider)
        _ = await drain(provider)
        #expect(inner.requests.map(\.thinking) == [nil, nil])
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func `a failed lookup ends the request without contacting the provider, and the next request tries again`()
        async
    {
        let inner = ScriptedProvider([.reply("later")])
        let calls = Mutex(0)
        let provider = DeferredThinkingProvider(inner: inner) {
            let attempt = calls.withLock { value -> Int in
                value += 1
                return value
            }
            if attempt == 1 { throw Refused() }
            return .betweenTools
        }
        let failure = await drain(provider)
        #expect(failure as? Refused == Refused())
        #expect(inner.requests.isEmpty)
        let retried = await drain(provider)
        #expect(retried == nil)
        #expect(inner.requests.map(\.thinking) == [.betweenTools])
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func `the lookup does not change the rest of the request`() async {
        let inner = ScriptedProvider([.reply("a")])
        let provider = DeferredThinkingProvider(inner: inner) { .disabled }
        let original = ModelRequest(
            model: "chosen", maxTokens: 777, systemPrompt: ["rules"],
            messages: [ModelMessage(role: .user, blocks: [.text("hello")])], tools: [])
        do { for try await _ in provider.stream(original) {} } catch { Issue.record("unexpected \(error)") }
        var expected = original
        expected.thinking = .disabled
        #expect(inner.requests == [expected])
    }

    @Test func `the provider's own events and failures pass through unchanged`() async {
        let inner = ScriptedProvider([.reply("hello"), .permanent])
        let provider = DeferredThinkingProvider(inner: inner) { .effort(.low) }
        var text = ""
        do {
            for try await event in provider.stream(request()) {
                if case .textDelta(_, let delta) = event { text += delta }
            }
        } catch { Issue.record("unexpected \(error)") }
        #expect(text == "hello")
        let failure = await drain(provider)
        #expect(failure is ScriptedProvider.PermanentFailure)
    }
}
