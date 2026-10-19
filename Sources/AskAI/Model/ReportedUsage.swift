internal import AemiJSON

/// Token counts as a server reports them in an OpenAI protocol, which names the same three counts differently in
/// chat completions (`prompt_tokens`, `completion_tokens`) and in the Responses API (`input_tokens`, `output_tokens`).
struct ReportedUsage: Decodable, Sendable {
    private let prompt: Int?
    private let completion: Int?
    private let cached: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case inputTokens = "input_tokens"
        case completionTokens = "completion_tokens"
        case outputTokens = "output_tokens"
        case promptDetails = "prompt_tokens_details"
        case inputDetails = "input_tokens_details"
    }

    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: CodingKeys.self)
        prompt =
            try keys.decodeIfPresent(Int.self, forKey: .promptTokens)
            ?? keys.decodeIfPresent(Int.self, forKey: .inputTokens)
        completion =
            try keys.decodeIfPresent(Int.self, forKey: .completionTokens)
            ?? keys.decodeIfPresent(Int.self, forKey: .outputTokens)
        let details =
            try keys.decodeIfPresent(CachedTokenDetails.self, forKey: .promptDetails)
            ?? keys.decodeIfPresent(CachedTokenDetails.self, forKey: .inputDetails)
        cached = details?.cachedTokens
    }

    /// The counts in neutral terms: `input` counts only prompt tokens the server did not read from its cache.
    var tokens: TokenUsage { TokenUsage(prompt: prompt, completion: completion, cached: cached) }
}
