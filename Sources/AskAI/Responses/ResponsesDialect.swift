/// How a Responses server's requests differ from the plain API's: what it refuses, insists on, or wants to be told.
public struct ResponsesDialect: Sendable, Equatable {
    /// Whether requests carry `max_output_tokens`; the ChatGPT backend refuses one.
    public var sendsOutputLimit: Bool
    /// A key the server caches the prompt under, sent as `prompt_cache_key`.
    public var promptCacheKey: String?
    /// Instructions to send when ask has none, for a server that insists on some.
    public var fallbackInstructions: String?

    /// A dialect with these differences.
    public init(sendsOutputLimit: Bool = true, promptCacheKey: String? = nil, fallbackInstructions: String? = nil) {
        self.sendsOutputLimit = sendsOutputLimit
        self.promptCacheKey = promptCacheKey
        self.fallbackInstructions = fallbackInstructions
    }

    /// The plain API: OpenAI's and llama.cpp's.
    public static let standard = ResponsesDialect()
}
