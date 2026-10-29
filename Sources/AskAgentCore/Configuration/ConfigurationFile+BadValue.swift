internal import AskAI

extension ConfigurationFile {
    /// A string that is not one of the key's choices.
    struct BadValue: Error {
        let key: String
        let value: String

        var reason: String {
            switch key {
                case "thinking": "must be one of: \(ThinkingLevel.choices)"
                case "keepAwake": "is \"\(value)\": use \(KeepAwakeMode.choices)"
                case "credentials": "is \"\(value)\": use \(CredentialStorage.choices)"
                case "sandbox.network": "is \"\(value)\": use \"none\", \"localhost\" or \"any\""
                case "ui.tools", "ui.thinking", "ui.code": "is \"\(value)\": use \"folded\" or \"open\""
                // @dl:accept -- one message per key: the table is the data
                case "ui.sidebar": "is \"\(value)\": use \"open\" or \"closed\""
                case "ui.mouse", "ui.copyOnSelect", "skills.enabled", "ui.tint", "ui.separator", "ui.padding",
                    "ui.markdown", "ui.localizedDurations", "ui.jobAutoReturnWhenFocused",
                    "ui.abortTurnRequiresConfirmation", "ui.escapeInterruptRequiresConfirmation", "ui.onlyUsefulModels":
                    "is \"\(value)\": use \"on\" or \"off\""
                case "ui.interruptKeys": "is \"\(value)\": use \"esc\", \"ctrl-c\" or \"both\""
                case "compactAt": "is \(value): use \(CompactionThreshold.expected)"
                case "ui.interruptSendsQueued": "is \"\(value)\": use \"none\", \"next\" or \"all\""
                default: "is \"\(value)\": use \"workspace\", \"anywhere\" or a list of paths"
            }
        }
    }
}
