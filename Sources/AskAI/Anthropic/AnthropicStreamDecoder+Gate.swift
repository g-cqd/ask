extension AnthropicStreamDecoder {
    /// A 429 while the Claude subscription's own headers say every quota allows requests (roadmap 0165, ADR-0007): the subscription gate
    /// answers a request shape it rejects this way, so it may not be a rate limit at all. It stays retryable, because a genuine burst
    /// limit reads the same; the words say what else it may be, and give the request id for a report.
    static func gateSuspected(_ failure: ProviderFailure, headers: [String: String]) -> ProviderFailure {
        let prefix = "anthropic-ratelimit-unified-"
        guard failure.kind == .rateLimited, headers[prefix + "status"] == "allowed",
            ["5h-", "7d-"].allSatisfy({ headers[prefix + $0 + "status"].map { $0 == "allowed" } ?? true })
        else { return failure }
        let message =
            "Anthropic answered with a rate limit while your Claude subscription's quotas still allow requests, so it may be refusing"
            + " the shape of the request rather than its rate\(requestID(headers)). If it keeps happening, another connection or an"
            + " Anthropic API key can serve it. Anthropic said: " + failure.message
        return ProviderFailure(kind: failure.kind, message: message)
    }

    /// Anthropic's refusal of a subscription credential outside Claude Code: the request's shape, not the account, so sending it again
    /// will not help. Reported publicly for subscription tokens sent without the expected identity; not met in ask's recordings.
    static func credentialRefused(_ failure: ProviderFailure, headers: [String: String]) -> ProviderFailure {
        guard failure.message.lowercased().contains("only authorized for use with claude code") else { return failure }
        let message =
            "Anthropic refused this request's shape for a Claude subscription\(requestID(headers)); sending it again will not help."
            + " An Anthropic API key or another connection can serve it. Anthropic said: " + failure.message
        return ProviderFailure(kind: failure.kind, message: message)
    }

    /// " (request id …)" from the response's `request-id`, for a report; empty when there is none or it does not look like one.
    static func requestID(_ headers: [String: String]) -> String {
        guard let id = headers["request-id"], (1 ... 80).contains(id.utf8.count),
            id.utf8.allSatisfy({
                ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 95 || $0 == 45
            })
        else { return "" }
        return " (request id \(id))"
    }
}
