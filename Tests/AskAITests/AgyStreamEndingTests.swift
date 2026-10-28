internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// The Cloud Code stream, against bodies recorded from a real account on 2026-10-24 (ids, traces and thought signatures replaced), and
/// against synthetic events for what the recording did not show. A synthetic case says so.
/// How a Cloud Code stream ends and fails: usage, stop reasons, errors and blocked prompts.
struct AgyStreamEndingTests {
    @Test func `thought tokens count as output and cached tokens come out of the input`() throws {
        let usage =
            #""usageMetadata":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":5,"thoughtsTokenCount":7}"#
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"x"}"#, finish: "STOP", usage: usage)
        ])
        #expect(
            events.contains(
                .messageDelta(stopReason: .endTurn, usage: TokenUsage(input: 60, output: 12, cacheRead: 40))))
    }

    @Test func `usage is the last the server reported, and unknown when it reported none`() throws {
        let later = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(
                parts: #"{"text":"x"}"#, usage: #""usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1}"#),
            AgyStreamFixtures.chunk(
                parts: #"{"text":""}"#, finish: "STOP",
                usage: #""usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":9}"#)
        ])
        #expect(later.contains(.messageDelta(stopReason: .endTurn, usage: TokenUsage(input: 1, output: 9))))
        let none = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"x"}"#, finish: "STOP", usage: #""x":1"#)
        ])
        #expect(none.contains(.messageDelta(stopReason: .endTurn, usage: TokenUsage())))
    }

    /// Only `STOP` was observed. The others are Google's documented finish reasons, mapped to what the loop does about each.
    @Test func `finish reasons map to stop reasons, and an unknown one is kept as it came`() throws {
        let table: [(String, StopReason)] = [
            ("STOP", .endTurn), ("MAX_TOKENS", .maxTokens), ("SAFETY", .refusal), ("RECITATION", .refusal),
            ("BLOCKLIST", .refusal), ("PROHIBITED_CONTENT", .refusal), ("SPII", .refusal), ("IMAGE_SAFETY", .refusal),
            ("MALFORMED_FUNCTION_CALL", .other("MALFORMED_FUNCTION_CALL")),
            ("SOMETHING_NEW", .other("SOMETHING_NEW"))
        ]
        for (wire, expected) in table {
            let events = try AgyStreamFixtures.decode(lines: [
                AgyStreamFixtures.chunk(parts: #"{"text":"x"}"#, finish: wire)
            ])
            #expect(
                events.contains(.messageDelta(stopReason: expected, usage: TokenUsage(input: 3, output: 2))), "\(wire)")
        }
    }

    @Test func `a call makes a stopped turn a tool-use turn, but not a cut or refused one`() throws {
        let call = #"{"functionCall":{"id":"1","name":"f","args":{}}}"#
        for (wire, expected) in [("STOP", StopReason.toolUse), ("MAX_TOKENS", .maxTokens), ("SAFETY", .refusal)] {
            let events = try AgyStreamFixtures.decode(lines: [AgyStreamFixtures.chunk(parts: call, finish: wire)])
            #expect(
                events.contains(.messageDelta(stopReason: expected, usage: TokenUsage(input: 3, output: 2))), "\(wire)")
        }
    }

    @Test func `a stream that ends with no finish reason is unfinished, and so is an empty one`() {
        #expect(throws: OpenAIStreamError.unfinished) {
            try AgyStreamFixtures.decode(lines: [AgyStreamFixtures.chunk(parts: #"{"text":"x"}"#)])
        }
        #expect(throws: OpenAIStreamError.unfinished) { try AgyStreamFixtures.decode(lines: []) }
        #expect(OpenAIStreamError.unfinished.isRetryable)
    }

    @Test func `data that is not this protocol's JSON is malformed, naming its bytes`() {
        for bad in ["", "not json", "[]", "7", "null", #"{"response":7}"#, #"{"response":{"candidates":7}}"#] {
            #expect(throws: OpenAIStreamError.malformed(event: bad), "\(bad)") {
                try AgyStreamFixtures.decode(lines: [bad])
            }
        }
        #expect(!OpenAIStreamError.malformed(event: "x").isRetryable)
    }

    /// Synthetic: the recording had no in-stream error. The shape is the one Cloud Code returns with an HTTP status.
    @Test func `an error event is a provider failure classified by its code`() {
        let table: [(Int, ProviderFailure.Kind)] = [
            (400, .invalidRequest), (401, .authentication), (403, .permission), (404, .notFound), (429, .rateLimited),
            (503, .overloaded), (500, .server)
        ]
        for (code, kind) in table {
            let line = #"{"error":{"code":\#(code),"message":"words","status":"SOME_STATUS"}}"#
            #expect(throws: OpenAIStreamError.provider(ProviderFailure(kind: kind, message: "words")), "\(code)") {
                try AgyStreamFixtures.decode(lines: [line])
            }
        }
    }

    @Test func `an HTTP error body gives the same failure, from the shape Cloud Code was observed to send`() {
        let body = Array(
            #"{"error":{"code":503,"message":"No capacity available for model gemini-2.5-pro on the server","status":"UNAVAILABLE"}}"#
                .utf8)
        #expect(
            AgyStreamDecoder.failure(inErrorBody: body)
                == ProviderFailure(
                    kind: .overloaded, message: "No capacity available for model gemini-2.5-pro on the server"))
        #expect(AgyStreamDecoder.failure(inErrorBody: Array("not json".utf8)) == nil)
        #expect(AgyStreamDecoder.failure(inErrorBody: Array(#"{"nothing":1}"#.utf8)) == nil)
        #expect(AgyStreamDecoder.failure(inErrorBody: Array(#"{"error":{"message":"m"}}"#.utf8))?.message == "m")
    }

    @Test func `a failure's words are made safe for a terminal and bounded`() {
        let hostile = "a\\u001b[31mred\\u0007 \\u0000z\\u007f\\u009b\\u0080\\u009f" + String(repeating: "x", count: 600)
        let body = Array(#"{"error":{"code":500,"message":"\#(hostile)"}}"#.utf8)
        let message = AgyStreamDecoder.failure(inErrorBody: body)?.message ?? ""
        #expect(!message.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F })
        #expect(message.hasPrefix("a [31mred") && message.count == 300)
    }

    /// Synthetic: no prompt was blocked in the recordings.
    @Test func `a blocked prompt is a refusal with a notice, and an unspecified or odd reason is not`() throws {
        let blocked =
            #"{"response":{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"},"modelVersion":"m","responseId":"r"}}"#
        let events = try AgyStreamFixtures.decode(lines: [blocked])
        #expect(events.contains(.notice("The request was blocked by the provider (PROHIBITED_CONTENT).")))
        #expect(events.contains(.messageDelta(stopReason: .refusal, usage: TokenUsage())))
        for reason in ["BLOCKED_REASON_UNSPECIFIED", "lower case", "X"] {
            let line =
                #"{"response":{"promptFeedback":{"blockReason":"\#(reason)"},"modelVersion":"m","responseId":"r"}}"#
            #expect(throws: OpenAIStreamError.unfinished, "\(reason)") { try AgyStreamFixtures.decode(lines: [line]) }
        }
    }

    @Test func `the done marker, if the server sends one, is ignored`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(parts: #"{"text":"x"}"#, finish: "STOP"), "[DONE]"
        ])
        #expect(events.contains(.messageStopped))
    }

    @Test func `a usage with only a prompt count has an unknown output, not zero`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(
                parts: #"{"text":"x"}"#, finish: "STOP", usage: #""usageMetadata":{"promptTokenCount":5}"#)
        ])
        #expect(events.contains(.messageDelta(stopReason: .endTurn, usage: TokenUsage(input: 5))))
    }

    @Test func `a block reason of 64 letters is one and of 65 is not`() throws {
        for (length, blocked) in [(64, true), (65, false), (3, true)] {
            let reason = String(repeating: "R", count: length)
            let line =
                #"{"response":{"promptFeedback":{"blockReason":"\#(reason)"},"modelVersion":"m","responseId":"r"}}"#
            if blocked {
                #expect(
                    try AgyStreamFixtures.decode(lines: [line])
                        .contains(.notice("The request was blocked by the provider (\(reason))."))
                )
            } else {
                #expect(throws: OpenAIStreamError.unfinished, "\(length)") {
                    try AgyStreamFixtures.decode(lines: [line])
                }
            }
        }
    }

    /// Synthetic: no length refusal was provoked. The wording is the one `ProviderFailure` already recognises.
    @Test func `a refusal for length is a context overflow, with the window the server named`() {
        let body = Array(
            #"{"error":{"code":400,"message":"prompt is too long: the maximum context length is 1000 tokens","status":"INVALID_ARGUMENT"}}"#
                .utf8)
        let failure = AgyStreamDecoder.failure(inErrorBody: body)
        #expect(failure?.kind == .contextOverflow && failure?.contextWindow == 1000)
        let other = Array(#"{"error":{"code":500,"message":"the maximum context length is 1000 tokens"}}"#.utf8)
        #expect(
            AgyStreamDecoder.failure(inErrorBody: other)?.kind == .server, "only a 400 is read as a refusal for length")
    }

    /// Recorded 2026-10-28 (roadmap 0069 U1): 137,838 tokens sent to `gpt-oss-120b-medium`. The message is the server's;
    /// the JSON envelope around it is assumed to be the one the other 400s use (the raw body was not captured).
    @Test func `the recorded Antigravity refusal for length is a context overflow with its window`() {
        let message = "The input (137838 tokens) is longer than the model's context length (131072 tokens)."
        let body = Array(#"{"error":{"code":400,"message":"\#(message)","status":"INVALID_ARGUMENT"}}"#.utf8)
        let failure = AgyStreamDecoder.failure(inErrorBody: body)
        #expect(failure?.kind == .contextOverflow && failure?.contextWindow == 131072)
    }

    @Test func `an error with no words is given some`() {
        let failure = AgyStreamDecoder.failure(inErrorBody: Array(#"{"error":{"code":503}}"#.utf8))
        #expect(failure == ProviderFailure(kind: .overloaded, message: "the provider reported an error"))
    }
}
