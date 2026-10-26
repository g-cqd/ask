/// The thinking levels a model can be asked for, as far as its catalog entry says, so a list offers what will be accepted.
public enum ThinkingOptions {
    /// What the list for one model holds.
    public struct Choices: Sendable, Equatable {
        /// The levels, in the order to show them, without the provider's own default, which is always offered.
        public let levels: [ThinkingLevel]
        /// Whether the catalog said so: false means the model's entry did not list levels, so these are what ask knows how to send, unverified.
        public let verified: Bool
        /// The level the server uses when none is asked for, when it said.
        public let serverDefault: ThinkingLevel?
    }

    /// The levels for `model`, or nil when its protocol has no thinking control at all.
    /// - Parameters:
    ///   - provider: where the model is served.
    ///   - descriptor: the model's catalog entry, or nil when none is known.
    /// - Returns: the levels, or nil when the provider has no control.
    public static func choices(for provider: ResolvedModel.Provider, descriptor: CatalogModel?) -> Choices? {
        switch provider {
            case .openAICompatible, .agy, .apple: return nil
            case .anthropic:
                guard let descriptor, descriptor.supportsThinking != false else {
                    return descriptor == nil ? Choices(levels: Self.every, verified: false, serverDefault: nil) : nil
                }
                var levels = descriptor.reasoningLevels.compactMap(ThinkingLevel.init(rawValue:))
                let modes = descriptor.thinkingModes
                if modes.contains(.enabled), levels.isEmpty {
                    levels = [.minimal, .low, .medium, .high, .xhigh, .max]
                }
                if modes.contains(.disabled) || modes.contains(.betweenTools) { levels.insert(.off, at: 0) }
                return Choices(levels: levels, verified: !modes.isEmpty, serverDefault: nil)
            case .codex, .openAIResponses:
                guard let descriptor, !descriptor.reasoningLevels.isEmpty else {
                    return Choices(levels: Self.every, verified: false, serverDefault: nil)
                }
                let levels = descriptor.reasoningLevels.compactMap {
                    $0 == "none" ? ThinkingLevel.off : ThinkingLevel(rawValue: $0)
                }
                return Choices(
                    levels: levels, verified: true,
                    serverDefault: descriptor.defaultReasoningLevel.flatMap(ThinkingLevel.init(rawValue:)))
        }
    }

    /// Every level ask can send, for a model whose entry lists none.
    private static let every: [ThinkingLevel] = [.off, .minimal, .low, .medium, .high, .xhigh, .max]
}
