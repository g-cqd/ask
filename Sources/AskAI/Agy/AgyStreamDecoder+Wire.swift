internal import AemiJSON

extension AgyStreamDecoder {
    /// The longest error message repeated to a person.
    private static let longestMessage = 300

    /// What the finish reason means. Only `STOP` has been observed; the others are Google's documented reasons.
    static func stopReason(_ wire: String, called: Bool) -> StopReason {
        switch wire {
            case "STOP": called ? .toolUse : .endTurn
            case "MAX_TOKENS": .maxTokens
            case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY": .refusal
            default: .other(wire)
        }
    }

    /// Cloud Code's usage: thought tokens count as output, and cached tokens are part of the prompt count.
    static func tokens(_ usage: JSON) -> TokenUsage {
        let answer = usage["candidatesTokenCount"].int
        let thoughts = usage["thoughtsTokenCount"].int
        let output = answer == nil && thoughts == nil ? nil : (answer ?? 0) + (thoughts ?? 0)
        return TokenUsage(
            prompt: usage["promptTokenCount"].int, completion: output, cached: usage["cachedContentTokenCount"].int)
    }

    /// Why a prompt was blocked, when the feedback names a reason.
    static func blockReason(_ feedback: JSON) -> String? {
        guard let reason = feedback["blockReason"].string, reason != "BLOCKED_REASON_UNSPECIFIED",
            (3 ... 64).contains(reason.utf8.count), reason.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || $0 == 95 })
        else { return nil }
        return reason
    }

    /// The failure an `error` object reports: its HTTP-style code classifies it.
    static func failure(_ error: JSON) -> ProviderFailure {
        let message = clean(error["message"].string ?? "")
        var kind = ProviderFailure.Kind(status: error["code"].int)
        if kind == .invalidRequest, ProviderFailure.Kind.describesContextOverflow(message) { kind = .contextOverflow }
        return ProviderFailure(
            kind: kind, message: message.isEmpty ? "the provider reported an error" : message,
            contextWindow: kind == .contextOverflow ? ProviderFailure.Kind.contextWindow(describedIn: message) : nil)
    }

    /// The server's reason in the body of a non-2xx response.
    public static func failure(inErrorBody body: [UInt8]) -> ProviderFailure? {
        guard let root = try? AemiJSON.parse(body).root, root["error"].isObject else { return nil }
        return failure(root["error"])
    }

    /// `text` with every control character a terminal would act on replaced by a space, cut to a sentence's length.
    private static func clean(_ text: String) -> String {
        let safe = text.unicodeScalars.map {
            $0.value < 0x20 || (0x7F ... 0x9F).contains($0.value) ? " " : Character($0)
        }
        return String(safe.prefix(longestMessage))
    }
}
