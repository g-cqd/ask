import Foundation
import Testing

@testable import AskAI

@Suite("Responses item identity follows stable output indexes without deduplicating text")
struct ResponsesIdentityTests {
    private func decode(_ frames: [String]) throws -> [ModelEvent] {
        var decoder = ResponsesStreamDecoder()
        var events: [ModelEvent] = []
        for frame in frames { try decoder.decode(SSEEvent(name: "message", data: Array(frame.utf8)), into: &events) }
        try decoder.finish(into: &events)
        return events
    }

    private func text(_ events: [ModelEvent]) -> String {
        events.compactMap { if case .textDelta(_, let text) = $0 { text } else { nil } }.joined()
    }

    @Test(arguments: [1, 7, 65536])
    func `recorded rotating IDs emit AUDIT once in one block regardless of byte delivery`(chunk: Int) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Fixtures/Responses/copilot-rotating-ids.sse")
        let bytes = Array(try Data(contentsOf: fixture))
        var framer = SSEDecoder()
        var decoder = ResponsesStreamDecoder()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        for offset in stride(from: 0, to: bytes.count, by: chunk) {
            try framer.feed(bytes[offset ..< Swift.min(bytes.count, offset + chunk)].span, into: &frames)
            for frame in frames { try decoder.decode(frame, into: &events) }
            frames.removeAll()
        }
        try decoder.finish(into: &events)
        #expect(text(events) == "AUDIT")
        #expect(events.filter { if case .blockStarted(_, .text) = $0 { true } else { false } }.count == 1)
        var assembler = ResponseAssembler()
        for event in events { try assembler.apply(event) }
        #expect(try assembler.finish().blocks == [.text("AUDIT")])
    }

    @Test func `separate indexed items retain identical legitimate text`() throws {
        let events = try decode([
            #"{"type":"response.output_text.delta","item_id":"first","output_index":0,"delta":"Hi"}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"first-done","content":[{"text":"Hi"}]}}"#,
            #"{"type":"response.output_text.delta","item_id":"second","output_index":1,"delta":"Hi"}"#,
            #"{"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"second-done","content":[{"text":"Hi"}]}}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        ])
        #expect(text(events) == "HiHi")
        #expect(events.filter { if case .blockStarted(_, .text) = $0 { true } else { false } }.count == 2)
    }

    @Test func `stable aliases support mixed indexed and ID only events`() throws {
        let events = try decode([
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"a"}}"#,
            #"{"type":"response.output_text.delta","item_id":"a","delta":"H"}"#,
            #"{"type":"response.content_part.added","item_id":"b","output_index":0,"part":{"type":"output_text","text":""}}"#,
            #"{"type":"response.output_text.delta","item_id":"b","delta":"i"}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","id":"b","content":[{"text":"Hi"}]}}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        ])
        #expect(text(events) == "Hi")
        #expect(events.filter { if case .blockStarted(_, .text) = $0 { true } else { false } }.count == 1)
    }

    @Test func `rotating function call IDs preserve one call and its argument fragments`() throws {
        let events = try decode([
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"a","call_id":"call-1","name":"read"}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"b","output_index":0,"delta":"{\"path\":"}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"c","output_index":0,"delta":"\"note\"}"}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"d","call_id":"call-1","name":"read","arguments":"{\"path\":\"note\"}"}}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        ])
        #expect(events.filter { if case .blockStarted(_, .toolUse) = $0 { true } else { false } }.count == 1)
        let arguments = events.compactMap { if case .toolInputDelta(_, let text) = $0 { text } else { nil } }.joined()
        #expect(arguments == #"{"path":"note"}"#)
    }

    @Test func `a message with an output index but no item ID still streams`() throws {
        var decoder = ResponsesStreamDecoder()
        var events: [ModelEvent] = []
        let first = #"{"type":"response.output_text.delta","output_index":0,"delta":"Hi"}"#
        try decoder.decode(SSEEvent(name: "message", data: Array(first.utf8)), into: &events)
        #expect(text(events) == "Hi")
        let done =
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","content":[{"text":"Hi"}]}}"#
        try decoder.decode(SSEEvent(name: "message", data: Array(done.utf8)), into: &events)
        #expect(text(events) == "Hi")
    }
}
