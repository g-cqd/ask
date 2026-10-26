extension ResolvedModel {
    /// How the model is named to the person: `model` for the built-in Anthropic provider, and `provider/model` for every other one,
    /// where `provider` is the connection's name, or the configuration's name for a configured provider.
    public var label: String {
        if let connection { return "\(connection.name)/\(model)" }
        switch provider {
            case .openAICompatible(let name, _, _, _), .openAIResponses(let name, _, _, _): return "\(name)/\(model)"
            case .codex: return "codex/\(model)"
            case .agy: return "agy/\(model)"
            case .anthropic: return model
        }
    }
}
