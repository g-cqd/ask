import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// A provider wrapped to say something about its credentials (ADR-0091): once per request, after the request is under way, and never at
/// the cost of the response.
@Suite("A noticing provider adds a notice to a stream and changes nothing else")
struct NoticingProviderTests {
    private struct Fixed: ModelProvider {
        let events: [ModelEvent]
        var failure: (any Error)?

        func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
            let (events, failure) = (events, failure)
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish(throwing: failure)
            }
        }
    }

    private struct Refused: Error {}

    private static let request = ModelRequest(
        model: "x", maxTokens: 10, systemPrompt: [], messages: [], tools: [])

    private static let turn: [ModelEvent] = [
        .messageStarted(id: "m", model: "x", usage: TokenUsage(input: 1)), .blockStarted(index: 0, .text),
        .textDelta(index: 0, "hi"), .blockStopped(index: 0), .messageDelta(stopReason: .endTurn, usage: TokenUsage()),
        .messageStopped
    ]

    private func events(_ provider: some ModelProvider) async throws -> [ModelEvent] {
        var seen: [ModelEvent] = []
        for try await event in provider.stream(Self.request) { seen.append(event) }
        return seen
    }

    @Test func `the notice follows the first event, and the rest of the stream is untouched and in order`() async throws
    {
        let provider = NoticingProvider(base: Fixed(events: Self.turn), notice: { "say this" })
        let seen = try await events(provider)
        #expect(seen == [Self.turn[0], .notice("say this")] + Self.turn.dropFirst())
    }

    @Test func `it is asked once per request, however long the stream`() async throws {
        let asked = Mutex(0)
        let provider = NoticingProvider(
            base: Fixed(events: Self.turn),
            notice: {
                asked.withLock { $0 += 1 }
                return nil
            })
        _ = try await events(provider)
        #expect(asked.withLock { $0 } == 1)
        _ = try await events(provider)
        #expect(asked.withLock { $0 } == 2)
    }

    @Test func `nothing is added when there is nothing to say`() async throws {
        let seen = try await events(NoticingProvider(base: Fixed(events: Self.turn), notice: { nil }))
        #expect(seen == Self.turn)
    }

    @Test func `a request that fails before any event still gets its notice, then its failure`() async throws {
        let provider = NoticingProvider(base: Fixed(events: [], failure: Refused()), notice: { "say this" })
        var seen: [ModelEvent] = []
        do {
            for try await event in provider.stream(Self.request) { seen.append(event) }
            Issue.record("the failure was swallowed")
        } catch {
            #expect(error is Refused)
        }
        #expect(seen == [.notice("say this")])
    }

    @Test func `a stream that ends without an event gets its notice`() async throws {
        let seen = try await events(NoticingProvider(base: Fixed(events: []), notice: { "say this" }))
        #expect(seen == [.notice("say this")])
    }

    @Test func `the loop runs a turn that carries a notice, and shows it`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-noticing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: FilePath(directory.appending(path: "s.jsonl").path), durability: .none))
        let loop = AgentLoop(
            provider: NoticingProvider(base: Fixed(events: Self.turn), notice: { "say this" }),
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "x", maximumTokens: 100, systemPrompt: [], maximumTurns: 2),
            context: ToolContext(workingDirectory: directory.path))
        var shown: [String] = []
        try await loop.run("go", in: file) { event in
            if case .model(.notice(let text)) = event { shown.append(text) }
        }
        #expect(shown == ["say this"])
    }
}
