public import AskAI

extension Configuration {
    /// `self` with the thinking level of the alias the run resolved to. The alias is a more specific choice than a
    /// configuration file or the built-in default, so it replaces those; `ASK_THINKING` and `--thinking` are this run's own say
    /// and are kept.
    /// - Parameters:
    ///   - level: the alias's level.
    ///   - alias: `connection/alias`, named as the source.
    /// - Returns: the configuration to run with.
    public func applying(aliasThinking level: ThinkingLevel, alias: String) -> Configuration {
        switch thinking.source {
            case .defaults, .file:
                var next = self
                next.thinking = Setting(value: level, source: .alias(alias))
                return next
            case .environment, .flag, .command, .session, .alias: return self
        }
    }
}
