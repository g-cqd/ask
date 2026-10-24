internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// The Cloud Code stream, against bodies recorded from a real account on 2026-10-24 (ids, traces and thought signatures replaced), and
/// against synthetic events for what the recording did not show. A synthetic case says so.
/// The Cloud Code stream decoded into events: the recorded streams, calls, text and thought. Endings are in `AgyStreamEndingTests`.
struct AgyStreamDecoderTests {
    @Test func `a Gemini call carries its signature in a block of its own before the call`() throws {
        let events = try AgyStreamFixtures.decode(fixture: "stream-gemini-call")
        #expect(
            events == [
                .messageStarted(id: "resp-test-1", model: "gemini-3-flash", usage: TokenUsage()),
                .blockStarted(index: 0, .thinking), .signatureDelta(index: 0, AgyStreamFixtures.marked()),
                .blockStopped(index: 0),
                .blockStarted(index: 1, .toolUse(id: "call_1218103", name: "calc")),
                .toolInputDelta(index: 1, #"{"b":53,"a":17}"#), .blockStopped(index: 1),
                .messageDelta(stopReason: .toolUse, usage: TokenUsage(input: 76, output: 18)), .messageStopped
            ])
    }

    @Test func `only the first of two parallel Gemini calls carries a signature, as the server sent it`() throws {
        let events = try AgyStreamFixtures.decode(fixture: "stream-gemini-parallel")
        #expect(
            events == [
                .messageStarted(id: "resp-test-1", model: "gemini-3-flash", usage: TokenUsage()),
                .blockStarted(index: 0, .thinking), .signatureDelta(index: 0, AgyStreamFixtures.marked()),
                .blockStopped(index: 0),
                .blockStarted(index: 1, .toolUse(id: "call_1252418", name: "calc")),
                .toolInputDelta(index: 1, #"{"a":2,"b":3}"#), .blockStopped(index: 1),
                .blockStarted(index: 2, .toolUse(id: "call_1252421", name: "calc")),
                .toolInputDelta(index: 2, #"{"b":5,"a":4}"#), .blockStopped(index: 2),
                .messageDelta(stopReason: .toolUse, usage: TokenUsage(input: 88, output: 32)), .messageStopped
            ])
    }

    @Test
    func
        `a Gemini text answer is one text block, and the empty thought and the signature on its last part make nothing`()
        throws
    {
        let events = try AgyStreamFixtures.decode(fixture: "stream-gemini-text")
        #expect(events.first == .messageStarted(id: "resp-test-1", model: "gemini-3-flash", usage: TokenUsage()))
        #expect(events.dropFirst().first == .blockStarted(index: 0, .text))
        let text = events.compactMap { if case .textDelta(0, let piece) = $0 { piece } else { nil } }.joined()
        #expect(text.hasPrefix("The ") || !text.isEmpty)
        #expect(!events.contains { if case .signatureDelta = $0 { true } else { false } })
        #expect(!events.contains { if case .blockStarted(_, .thinking) = $0 { true } else { false } })
        #expect(
            events.suffix(3) == [
                .blockStopped(index: 0), .messageDelta(stopReason: .endTurn, usage: TokenUsage(input: 9, output: 22)),
                .messageStopped
            ])
    }

    @Test func `a Claude call has no signature and the empty text around it makes no block`() throws {
        let events = try AgyStreamFixtures.decode(fixture: "stream-claude-call")
        #expect(
            events == [
                .messageStarted(id: "resp-test-1", model: "claude-sonnet-5-5-low", usage: TokenUsage()),
                .blockStarted(index: 0, .toolUse(id: "toolu_vrtx_016J7m5JCVqQ8Eq4i6xe8MVB", name: "calc")),
                .toolInputDelta(index: 0, #"{"a":17,"b":53}"#), .blockStopped(index: 0),
                .messageDelta(stopReason: .toolUse, usage: TokenUsage(input: 408, output: 67)), .messageStopped
            ])
    }

    @Test func `a long Claude answer is one text block`() throws {
        let events = try AgyStreamFixtures.decode(fixture: "stream-claude-text")
        #expect(
            events.filter { if case .blockStarted = $0 { true } else { false } } == [.blockStarted(index: 0, .text)])
        #expect(events.contains { if case .textDelta(0, let piece) = $0 { !piece.isEmpty } else { false } })
        #expect(
            events.suffix(2) == [
                .messageDelta(stopReason: .endTurn, usage: TokenUsage(input: 20, output: 43)), .messageStopped
            ])
    }

    @Test func `GPT-OSS thoughts are one thinking block before its call, with cached tokens taken out of the input`()
        throws
    {
        let events = try AgyStreamFixtures.decode(fixture: "stream-gptoss-call")
        #expect(events.dropFirst().first == .blockStarted(index: 0, .thinking))
        let thought = events.compactMap { if case .thinkingDelta(0, let piece) = $0 { piece } else { nil } }.joined()
        #expect(!thought.isEmpty)
        #expect(!events.contains { if case .signatureDelta = $0 { true } else { false } })
        #expect(events.contains { if case .blockStarted(1, .toolUse(_, "calc")) = $0 { true } else { false } })
        #expect(
            events.suffix(2) == [
                .messageDelta(stopReason: .toolUse, usage: TokenUsage(input: 78, output: 55, cacheRead: 64)),
                .messageStopped
            ])
    }

    @Test func `how the network cuts the stream does not change the events`() throws {
        for name in ["stream-gemini-call", "stream-gemini-parallel", "stream-claude-text", "stream-gptoss-call"] {
            let whole = try AgyStreamFixtures.decode(fixture: name)
            for size in [1, 2, 7, 64] {
                #expect(try AgyStreamFixtures.decode(fixture: name, chunk: size) == whole, "\(name) in \(size)s")
            }
        }
    }

    // MARK: - Calls

    // MARK: - Text and thought

    @Test func `text, thought, text and a call are four blocks, closed in order`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(
                parts:
                    #"{"text":"a"},{"text":"b"},{"thought":true,"text":"t"},{"text":"c"},{"functionCall":{"id":"1","name":"f","args":{}}}"#
            ),
            AgyStreamFixtures.stop
        ])
        #expect(
            events == [
                .messageStarted(id: "r1", model: "gemini-3-flash", usage: TokenUsage()),
                .blockStarted(index: 0, .text), .textDelta(index: 0, "a"), .textDelta(index: 0, "b"),
                .blockStopped(index: 0),
                .blockStarted(index: 1, .thinking), .thinkingDelta(index: 1, "t"), .blockStopped(index: 1),
                .blockStarted(index: 2, .text), .textDelta(index: 2, "c"), .blockStopped(index: 2),
                .blockStarted(index: 3, .toolUse(id: "1", name: "f")), .toolInputDelta(index: 3, "{}"),
                .blockStopped(index: 3),
                .messageDelta(stopReason: .toolUse, usage: TokenUsage(input: 3, output: 2)), .messageStopped
            ])
    }

    @Test func `whitespace before the first real text leads it, and whitespace alone makes no block`() throws {
        let led = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"\n"},{"text":"  "},{"text":"x"}"#), AgyStreamFixtures.stop
        ])
        #expect(led.contains(.textDelta(index: 0, "\n  x")))
        let alone = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"\n"}"#), AgyStreamFixtures.stop
        ])
        #expect(!alone.contains { if case .blockStarted = $0 { true } else { false } })
        let wrongKind = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"\n"},{"thought":true,"text":"t"}"#), AgyStreamFixtures.stop
        ])
        #expect(wrongKind.contains(.thinkingDelta(index: 0, "t")), "whitespace held for text does not lead a thought")
    }

    @Test func `only the first candidate is read`() throws {
        let line =
            #"{"response":{"candidates":[{"content":{"parts":[{"text":"one"}]},"finishReason":"STOP"},{"content":{"parts":[{"text":"two"}]}}],"modelVersion":"m","responseId":"r"}}"#
        let events = try AgyStreamFixtures.decode(lines: [line])
        #expect(events.contains(.textDelta(index: 0, "one")) && !events.contains(.textDelta(index: 0, "two")))
    }

    @Test func `a part this decoder does not know is reported, not dropped`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"inlineData":{"mimeType":"image/png","data":"AA"}}"#),
            AgyStreamFixtures.stop
        ])
        #expect(events.contains(.unrecognized(event: "part", type: "inlineData")))
    }

    // MARK: - Usage and stop reasons

    // MARK: - Failures

    @Test func `a part with only a signature or only the thought flag is nothing, not an unknown part`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"thoughtSignature":"S"},{"thought":true},{}"#), AgyStreamFixtures.stop
        ])
        #expect(!events.contains { if case .unrecognized = $0 { true } else { false } })
        #expect(!events.contains { if case .blockStarted = $0 { true } else { false } })
    }

    @Test func `whitespace that led one block does not lead another, nor leak across a call`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"\n"},{"text":"x"},{"thought":true,"text":"t"},{"text":"y"}"#),
            AgyStreamFixtures.stop
        ])
        #expect(events.contains(.textDelta(index: 0, "\nx")) && events.contains(.textDelta(index: 2, "y")))
        let across = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(
                parts: #"{"text":"\n"},{"functionCall":{"id":"1","name":"f","args":{}}},{"text":"z"}"#),
            AgyStreamFixtures.stop
        ])
        #expect(across.contains(.textDelta(index: 1, "z")), "the whitespace held before the call is gone")
    }

    @Test func `no event carries an empty delta, whatever empty parts the server sends`() throws {
        for name in [
            "stream-gemini-call", "stream-gemini-parallel", "stream-gemini-text", "stream-claude-call",
            "stream-claude-text", "stream-gptoss-call"
        ] {
            let empty = try AgyStreamFixtures.decode(fixture: name)
                .filter {
                    switch $0 {
                        case .textDelta(_, let piece), .thinkingDelta(_, let piece): piece.isEmpty
                        default: false
                    }
                }
            #expect(empty.isEmpty, "\(name)")
        }
        let inside = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"a"},{"text":""},{"thought":true,"text":""},{"text":"b"}"#),
            AgyStreamFixtures.stop
        ])
        #expect(
            inside.filter { if case .textDelta = $0 { true } else { false } } == [
                .textDelta(index: 0, "a"), .textDelta(index: 0, "b")
            ])
    }
}
