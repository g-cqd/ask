internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// How function calls come out of a Cloud Code stream: their ids, arguments and signatures.
struct AgyStreamCallTests {
    @Test func `a call with no id, an empty id or a repeated id gets one of its own`() throws {
        let line = AgyStreamFixtures.chunk(
            parts:
                #"{"functionCall":{"name":"a","args":{}}},{"functionCall":{"id":"","name":"b","args":{}}},{"functionCall":{"id":"x","name":"c","args":{}}},{"functionCall":{"id":"x","name":"d","args":{}}}"#,
            finish: "STOP")
        let events = try AgyStreamFixtures.decode(lines: [line])
        let ids = events.compactMap { if case .blockStarted(_, .toolUse(let id, _)) = $0 { id } else { nil } }
        #expect(ids.count == 4 && Set(ids).count == 4)
        #expect(ids.dropFirst(2).first == "x")
        #expect(ids.enumerated().allSatisfy { $0.offset == 2 || $0.element.hasPrefix("call_") })
    }

    @Test func `arguments that are missing or not an object become an empty object`() throws {
        let line = AgyStreamFixtures.chunk(
            parts:
                #"{"functionCall":{"id":"1","name":"a"}},{"functionCall":{"id":"2","name":"b","args":[1]}},{"functionCall":{"id":"3","name":"c","args":"x"}}"#,
            finish: "STOP")
        let inputs = try AgyStreamFixtures.decode(lines: [line])
            .compactMap { if case .toolInputDelta(_, let json) = $0 { json } else { nil } }
        #expect(inputs == ["{}", "{}", "{}"])
    }

    @Test func `an empty signature, or one on text, is not kept`() throws {
        let events = try AgyStreamFixtures.decode(lines: [
            AgyStreamFixtures.chunk(
                parts:
                    #"{"text":"hi","thoughtSignature":"abc"},{"functionCall":{"id":"1","name":"a","args":{}},"thoughtSignature":""}"#
            ),
            AgyStreamFixtures.stop
        ])
        #expect(!events.contains { if case .signatureDelta = $0 { true } else { false } })
    }

    @Test func `a signature is bound to the model the stream names, and to none when it names none`() throws {
        let call = #"{"functionCall":{"id":"1","name":"a","args":{}},"thoughtSignature":"SIG"}"#
        let named = try AgyStreamFixtures.decode(lines: [AgyStreamFixtures.chunk(parts: call), AgyStreamFixtures.stop])
        #expect(
            named.contains(
                .signatureDelta(index: 0, ReasoningProvenance.mark(scheme: "gemini/gemini-3-flash", payload: "SIG"))))
        let bare = #"{"response":{"candidates":[{"content":{"parts":[\#(call)]},"finishReason":"STOP"}]}}"#
        let unnamed = try AgyStreamFixtures.decode(lines: [bare])
        #expect(
            unnamed.contains(.signatureDelta(index: 0, ReasoningProvenance.mark(scheme: "gemini/", payload: "SIG"))))
    }
}
