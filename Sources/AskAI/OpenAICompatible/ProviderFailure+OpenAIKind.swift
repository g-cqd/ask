extension ProviderFailure.Kind {
    /// Fragments of the error `type` servers send, and the kind each means, tried in order: servers word their types
    /// differently (`rate_limit_exceeded`, `server_error`, `invalid_request_error`), so a type is matched by what it
    /// contains.
    private static let byTypeName: [(fragments: [String], kind: ProviderFailure.Kind)] = [
        // First: "insufficient_quota" also contains "quota", and a usage limit is not a rate limit.
        (["usage_limit", "insufficient_quota"], .usageLimit), (["rate_limit", "quota"], .rateLimited),
        (["overloaded"], .overloaded), (["server_error", "internal"], .server),
        (["authentication", "invalid_api_key"], .authentication), (["permission"], .permission),
        (["not_found"], .notFound), (["invalid_request"], .invalidRequest)
    ]

    /// The kind an OpenAI-compatible server means: a refusal for length first, whatever its type says, then the
    /// type's name, then the HTTP status. A status that says nothing keeps the provider's own name for the error.
    init(openAIType type: String?, status: Int?, code: String? = nil, message: String = "") {
        let named = type?.lowercased() ?? ""
        if named.contains("exceed_context_size") || code == "context_length_exceeded"
            || Self.describesContextOverflow(message)
        {
            self = .contextOverflow
        } else if let match = Self.byTypeName.first(where: { $0.fragments.contains(where: named.contains) }) {
            self = match.kind
        } else if case .other = Self(status: status), let type {
            self = .other(type)
        } else {
            self = Self(status: status)
        }
    }
}
