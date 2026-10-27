internal import Foundation
internal import Testing

@testable import AskAI

/// The decoder reproduces what a real Responses server sent, recorded byte for byte (`Tests/Fixtures/Responses`,
/// captured from Ornith-1.5-9B on llama.cpp by `capture_responses_sse.py`).
///
/// These llama.cpp recordings carry `item_id` but no `output_index`; the reply is `completed` even when cut at
/// `max_output_tokens`, and `encrypted_content` is empty. ResponsesIdentityTests separately cover a sanitized
/// rotating-ID Copilot recording. OpenAI's own stream has not
/// been recorded (it needs an account); the shapes it adds are covered by hand-built frames in
/// ``ResponsesStreamDecoderTests`` and checked against a live run when one is made (roadmap 0036).
@Suite("Recorded Responses streams from llama.cpp decode to the same response, however they are delivered")
struct ResponsesReplayTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Responses")

    private static func replay(_ name: String, chunk: Int = .max) throws -> (
        response: AssembledResponse, events: [ModelEvent]
    ) {
        let bytes = Array(try Data(contentsOf: fixtures.appending(path: "\(name).sse")))
        var framer = SSEDecoder()
        var decoder = ResponsesStreamDecoder()
        var assembler = ResponseAssembler()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        var offset = 0
        while offset < bytes.count {
            let end = Swift.min(bytes.count, offset + Swift.max(1, chunk))
            try framer.feed(bytes[offset ..< end].span, into: &frames)
            for frame in frames { try decoder.decode(frame, into: &events) }
            frames.removeAll()
            offset = end
        }
        try decoder.finish(into: &events)
        for event in events { try assembler.apply(event) }
        return (try assembler.finish(), events)
    }

    @Test func `the text recording is reasoning then the exact text, unsigned, ending the turn`() throws {
        let (response, _) = try Self.replay("llamacpp-text")
        #expect(response.stopReason == .endTurn)
        guard response.blocks.count == 2, case .thinking(let thought, let signature) = response.blocks[0],
            case .text(let text) = response.blocks[1]
        else {
            Issue.record("blocks: \(response.blocks)")
            return
        }
        #expect(text == "héllo wörld ✓")
        #expect(!thought.isEmpty)
        #expect(signature.isEmpty, "llama.cpp's encrypted_content is empty, so there is nothing to replay")
        #expect(response.usage.output == 28)
    }

    @Test func `the tool call recording is a read of notes/todo.txt, ending as tool use`() throws {
        let (response, _) = try Self.replay("llamacpp-tool-call")
        #expect(response.stopReason == .toolUse)
        let calls = response.blocks.compactMap { block -> (String, String)? in
            guard case .toolCall(_, let name, let input) = block else { return nil }
            return (name, String(decoding: input.bytes, as: UTF8.self))
        }
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "read")
        #expect(calls.first?.1 == #"{"path":"notes/todo.txt"}"#)
    }

    @Test func `the replayed history's answer mentions what the tool returned`() throws {
        let (response, _) = try Self.replay("llamacpp-replay")
        let text = response.blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
        #expect(text.lowercased().contains("milk"))
    }

    @Test(arguments: ["llamacpp-text", "llamacpp-tool-call", "llamacpp-replay", "llamacpp-truncated"])
    func `delivery in one byte, seven bytes or one piece gives the same events`(name: String) throws {
        let whole = try Self.replay(name).events
        #expect(try Self.replay(name, chunk: 1).events == whole)
        #expect(try Self.replay(name, chunk: 7).events == whole)
    }

    @Test func `a reply cut at the output limit is, on llama.cpp, reported as completed: the stop is end of turn`()
        throws
    {
        // A server quirk worth pinning: the real OpenAI sends response.incomplete here. The loop's own check
        // (a full window is a short reply that stopped) does not depend on this reason (ADR-0030).
        let (response, _) = try Self.replay("llamacpp-truncated")
        #expect(response.stopReason == .endTurn)
        #expect(response.usage.output == 16)
    }
}
