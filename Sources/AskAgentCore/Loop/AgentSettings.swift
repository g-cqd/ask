public import AskAI

/// What a run uses besides its tools.
public struct AgentSettings: Sendable, Equatable {
    public var model: String
    public var maximumTokens: Int
    public var systemPrompt: [String]
    /// The most requests one run may make, so a model that never stops calling tools cannot run forever.
    public var maximumTurns: Int
    /// Compact before a request once the context reached this many tokens (the newest response's prompt plus
    /// its reply); nil never does,
    /// except when the context window is full.
    public var compactAtTokens: Int?
    /// How much of the recent conversation a compaction keeps word for word, in bytes of text.
    public var keepRecentBytes: Int
    /// How much tool output one turn may add, in bytes, shared by its calls; nil for no limit beyond the tools' own.
    public var toolOutputBytes: Int?
    /// The provider-compatible control; every normal and compaction request carries it unchanged.
    public var thinking: ThinkingControl?
    /// Whether the model takes images; anything but true withholds them from every request, with a line saying so.
    public var acceptsImages: Bool?

    /// The default threshold: Anthropic's own default trigger for server-side compaction.
    public static let defaultCompactAtTokens = 150_000

    /// Settings with these values.
    /// - Parameters:
    ///   - model: the model to request.
    ///   - maximumTokens: the reply limit per request.
    ///   - systemPrompt: ask's instructions, as text blocks.
    ///   - maximumTurns: the most requests one run may make.
    ///   - compactAtTokens: the prompt size that triggers compaction, or nil.
    ///   - keepRecentBytes: how much recent text a compaction keeps; about 20,000 tokens by default.
    ///   - toolOutputBytes: how much tool output one turn may add, or nil.
    ///   - thinking: the concrete control chosen from user policy and provider metadata, or nil for defaults.
    ///   - acceptsImages: whether the model takes images; anything but true withholds them.
    public init(
        model: String, maximumTokens: Int, systemPrompt: [String], maximumTurns: Int,
        // @dl:accept -- an initializer's optional parameters with nil defaults; the lists are the data
        compactAtTokens: Int? = defaultCompactAtTokens, keepRecentBytes: Int = 80_000, toolOutputBytes: Int? = nil,
        thinking: ThinkingControl? = nil, acceptsImages: Bool? = nil
    ) {
        self.acceptsImages = acceptsImages
        self.toolOutputBytes = toolOutputBytes
        self.thinking = thinking
        self.model = model
        self.maximumTokens = maximumTokens
        self.systemPrompt = systemPrompt
        self.maximumTurns = maximumTurns
        self.compactAtTokens = compactAtTokens
        self.keepRecentBytes = keepRecentBytes
    }
}
