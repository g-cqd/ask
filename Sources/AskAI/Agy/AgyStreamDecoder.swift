internal import AemiJSON

/// Turns a Cloud Code stream into ``ModelEvent``s, one server-sent event at a time.
///
/// Each event wraps a Gemini `GenerateContentResponse` in `response`. Its first candidate carries parts: text, thought text (which for
/// Gemini 3 arrives empty), and function calls, each with the id the server gave it. Usage is cumulative and the finish reason comes
/// on a last, empty text part, so the end of the response is reported when the stream ends.
///
/// Consecutive parts of one kind are one block. A block starts at its first real text, so the empty parts around a response make none
/// (whitespace alone would be refused by a provider such as Anthropic if a session later moved to it). A function call's
/// `thoughtSignature` is kept in a thinking block of its own just before the call, behind a provenance marker that names the model the
/// stream reported, so it goes back to that model and no other (ADR-0033). Failures are ``OpenAIStreamError``, as the Responses
/// decoder's are: malformed data, an unfinished stream, and a failure the provider reported.
public struct AgyStreamDecoder: ModelEventDecoding {
    /// The provenance scheme a signature is stored under, followed by the model that issued it.
    static let schemePrefix = "gemini/"

    enum Run { case text, thinking }

    var started = false
    var model = ""
    var nextBlock = 0
    var open: (run: Run, index: Int)?
    var held: (run: Run, text: String)?
    var sawCall = false
    var callIDs: Set<String> = []
    var finishReason: String?
    var blocked: String?
    var usage = TokenUsage()

    /// A decoder at the start of a response.
    public init() {}

    /// Decodes one event, appending what it means to `events`.
    /// - Throws: ``OpenAIStreamError/malformed`` for data that is not this protocol's JSON, ``OpenAIStreamError/provider(_:)`` for an
    ///   error event.
    public mutating func decode(_ frame: SSEEvent, into events: inout [ModelEvent]) throws(OpenAIStreamError) {
        if frame.data == Array("[DONE]".utf8) { return }
        let chunk = try Self.chunk(of: frame.data)
        if !started {
            started = true
            model = chunk["modelVersion"].string ?? ""
            events.append(.messageStarted(id: chunk["responseId"].string ?? "", model: model, usage: TokenUsage()))
        }
        if let reason = Self.blockReason(chunk["promptFeedback"]) { blocked = reason }
        if let candidate = chunk["candidates"].array?.first {
            for part in candidate["content"]["parts"].array ?? [] { handle(part, into: &events) }
            if let reason = candidate["finishReason"].string { finishReason = reason }
        }
        if chunk["usageMetadata"].isObject { usage = Self.tokens(chunk["usageMetadata"]) }
    }

    /// The Gemini response inside an event's data, which wraps it in `response`.
    private static func chunk(of data: [UInt8]) throws(OpenAIStreamError) -> JSON {
        guard let root = try? AemiJSON.parse(data).root, root.isObject else {
            throw .malformed(of: data)
        }
        if root["error"].isObject { throw .provider(failure(root["error"])) }
        let wrapped = root["response"]
        if wrapped.exists, !wrapped.isObject { throw .malformed(of: data) }
        let chunk = wrapped.exists ? wrapped : root
        if chunk["candidates"].exists, chunk["candidates"].array == nil { throw .malformed(of: data) }
        return chunk
    }

    /// Closes every block still open and ends the response.
    /// - Throws: ``OpenAIStreamError/unfinished`` when no finish reason arrived and nothing blocked the prompt, which means the stream
    ///   was cut off or never began.
    public mutating func finish(into events: inout [ModelEvent]) throws(OpenAIStreamError) {
        let stop: StopReason
        if let finishReason {
            stop = Self.stopReason(finishReason, called: sawCall)
        } else if let blocked {
            events.append(.notice("The request was blocked by the provider (\(blocked))."))
            stop = .refusal
        } else {
            throw .unfinished
        }
        closeOpen(into: &events)
        events.append(.messageDelta(stopReason: stop, usage: usage))
        events.append(.messageStopped)
    }
}
