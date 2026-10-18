internal import AskAI

/// What a run uses besides its tools.
public struct AgentSettings: Sendable, Equatable {
    public var model: String
    public var maximumTokens: Int
    public var systemPrompt: [String]
    /// The most requests one run may make, so a model that never stops calling tools cannot run forever.
    public var maximumTurns: Int

    /// Settings with these values.
    public init(model: String, maximumTokens: Int, systemPrompt: [String], maximumTurns: Int) {
        self.model = model
        self.maximumTokens = maximumTokens
        self.systemPrompt = systemPrompt
        self.maximumTurns = maximumTurns
    }
}
