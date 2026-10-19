/// The part of a usage report that says how many prompt tokens the server read from its cache. Both OpenAI protocols
/// report it under this name, in a details object.
struct CachedTokenDetails: Decodable, Sendable {
    let cachedTokens: Int?

    enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
}
