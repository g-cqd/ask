extension ThinkingControl {
    /// Selects a concrete request control without changing the user's requested level to another one.
    /// - Parameters:
    ///   - level: the requested setting.
    ///   - model: the selected destination and raw model id.
    ///   - descriptor: metadata for exactly that model, or nil when unknown.
    ///   - maximumTokens: the actual request's output ceiling, including any thinking budget.
    /// - Returns: nil for provider defaults or an already non-thinking model's off request.
    /// - Throws: ``ThinkingError`` when the request cannot be represented.
    public static func select(
        _ level: ThinkingLevel, model: ResolvedModel, descriptor: CatalogModel?, maximumTokens: Int
    ) throws(ThinkingError) -> ThinkingControl? {
        if level == .providerDefault { return nil }
        let matching = descriptor.flatMap { $0.id == model.model ? $0 : nil }
        switch model.provider {
            case .anthropic:
                guard let matching else { throw .missingCapabilities(model: model.model) }
                return try native(level, descriptor: matching, maximumTokens: maximumTokens)
            case .codex, .openAIResponses:
                let wire = level == .off ? "none" : level.rawValue
                if let matching, !matching.reasoningLevels.isEmpty, !matching.reasoningLevels.contains(wire) {
                    throw .unavailable(model: model.model, level: level, available: matching.reasoningLevels)
                }
                return level == .off ? .disabled : .effort(level)
            case .openAICompatible: throw .unsupportedProtocol("OpenAI chat completions")
            case .agy: throw .unsupportedProtocol("Antigravity")
        }
    }

    private static func native(
        _ level: ThinkingLevel, descriptor: CatalogModel, maximumTokens: Int
    ) throws(ThinkingError) -> ThinkingControl? {
        if descriptor.supportsThinking == false {
            if level == .off { return nil }
            throw .unavailable(model: descriptor.id, level: level, available: ["off"])
        }
        let modes = descriptor.thinkingModes
        if level == .off {
            if modes.contains(.disabled) { return .disabled }
            if modes.contains(.betweenTools) { return .betweenTools }
        } else {
            if modes.contains(.adaptive), descriptor.reasoningLevels.contains(level.rawValue) { return .effort(level) }
            if modes.contains(.enabled) {
                return try legacyBudget(level, descriptor: descriptor, maximumTokens: maximumTokens)
            }
        }
        if modes.isEmpty { throw .missingCapabilities(model: descriptor.id) }
        var available = descriptor.reasoningLevels
        if modes.contains(.disabled) || modes.contains(.betweenTools) { available.insert("off", at: 0) }
        throw .unavailable(model: descriptor.id, level: level, available: available)
    }

    /// Legacy policy, not a provider's named effort: 1/2/8/16/32/64 Ki tokens, capped to reserve 1024 answer tokens.
    /// The concrete cap is reported by the composition layer. A separately supported effort is also sent when known.
    private static func legacyBudget(
        _ level: ThinkingLevel, descriptor: CatalogModel, maximumTokens: Int
    ) throws(ThinkingError) -> ThinkingControl {
        guard maximumTokens >= 2048 else { throw .insufficientOutput(minimum: 2048, available: maximumTokens) }
        let preferred: Int
        switch level {
            case .minimal: preferred = 1024
            case .low: preferred = 2048
            case .medium: preferred = 8192
            case .high: preferred = 16384
            case .xhigh: preferred = 32768
            case .max: preferred = 65536
            case .off, .providerDefault: throw .invalidControl("a budget requires an active level")
        }
        return .budget(
            tokens: min(preferred, maximumTokens - 1024),
            effort: descriptor.reasoningLevels.contains(level.rawValue) ? level : nil)
    }
}
