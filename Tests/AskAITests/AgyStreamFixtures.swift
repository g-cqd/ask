internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// The Cloud Code stream, against bodies recorded from a real account on 2026-10-24 (ids, traces and thought signatures replaced), and
/// against synthetic events for what the recording did not show. A synthetic case says so.
/// Recorded streams, the framing they travel in, and the synthetic events the tests add.
enum AgyStreamFixtures {
    static let signature = String(String(repeating: "c2lnbmF0dXJl", count: 12).prefix(140))

    static func fixture(_ name: String) throws -> [UInt8] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Agy/\(name).sse")
        return Array(try Data(contentsOf: url))
    }

    /// Frames `bytes` the way the transport does, in chunks of `size`, and decodes every event.
    static func decode(_ bytes: [UInt8], chunk size: Int = 1 << 20) throws -> [ModelEvent] {
        var framer = SSEDecoder()
        var decoder = AgyStreamDecoder()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        var start = 0
        while start < bytes.count {
            let end = min(start + size, bytes.count)
            try framer.feed(Array(bytes[start ..< end]).span, into: &frames)
            start = end
        }
        for frame in frames { try decoder.decode(frame, into: &events) }
        try decoder.finish(into: &events)
        return events
    }

    static func decode(fixture name: String, chunk: Int = 1 << 20) throws -> [ModelEvent] {
        try decode(fixture(name), chunk: chunk)
    }

    /// One synthetic data line per chunk, as the server frames it.
    static func decode(lines: [String]) throws(OpenAIStreamError) -> [ModelEvent] {
        var decoder = AgyStreamDecoder()
        var events: [ModelEvent] = []
        for line in lines { try decoder.decode(SSEEvent(name: "message", data: Array(line.utf8)), into: &events) }
        try decoder.finish(into: &events)
        return events
    }

    static func chunk(
        parts: String, finish: String? = nil,
        usage: String = #""usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":2}"#,
        extra: String = ""
    ) -> String {
        let reason = finish.map { #","finishReason":"\#($0)""# } ?? ""
        return
            #"{"response":{"candidates":[{"content":{"role":"model","parts":[\#(parts)]}\#(reason)}],\#(usage),"modelVersion":"gemini-3-flash","responseId":"r1"\#(extra)}}"#
    }

    static let stop = chunk(parts: #"{"text":""}"#, finish: "STOP")

    static func marked(_ model: String = "gemini-3-flash") -> String {
        ReasoningProvenance.mark(scheme: "gemini/" + model, payload: signature)
    }

    // MARK: - Recorded streams
}
