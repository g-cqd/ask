internal import AskAI
internal import AskAgentCore

extension RunSettings {
    /// An explicit request stays visible, including a default/reset; an entirely unset setting adds no screen work.
    var thinkingTag: String? {
        let setting = configuration.thinking
        guard setting.source != .defaults || setting.value != .providerDefault else { return nil }
        return "thinking \(setting.value.rawValue)"
    }
}
