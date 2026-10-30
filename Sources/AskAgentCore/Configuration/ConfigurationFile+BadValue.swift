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
                case "approvals.default": "is \"\(value)\": use \"ask\" or \"allow\""
                case "approvals.remember": "is \"\(value)\": use \"anything\", \"narrowing\" or \"none\""
                case "credentials": "is \"\(value)\": use \(CredentialStorage.choices)"
                case "sandbox.network": "is \"\(value)\": use \"none\", \"localhost\" or \"any\""
                // The names roadmap 0154 replaced, refused under the name the file used.
                case "ui.tools", "ui.thinking", "ui.code": "is \"\(value)\": use \"folded\" or \"open\""
                case "ui.localizedDurations", "ui.onlyUsefulModels", "ui.escapeInterruptRequiresConfirmation",
                    "ui.abortTurnRequiresConfirmation":
                    "is \"\(value)\": use \"on\" or \"off\""
                case "ui.durations": "is \"\(value)\": use \"words\" or \"clock\""
                case "ui.stopTwice": "names \"\(value)\": use \"esc\" and \"ctrl-c\""
                // @dl:accept -- one message per key: the table is the data
                case "ui.sidebar": "is \"\(value)\": use \"open\" or \"closed\""
                case "ui.mouse", "ui.copyOnSelect", "skills.enabled", "ui.tint", "ui.separator", "ui.padding",
                    "ui.markdown", "ui.leaveFinishedJob", "ui.listAllModels", "ui.fold.tools", "ui.fold.thinking",
                    "ui.fold.code",
                    "keepDisplayAwake":
                    "is \"\(value)\": use true or false"
                case "ui.showTimeout": "is \"\(value)\": use \"auto\", \"always\" or \"never\""
                case "ui.timeoutLabel": "must be 1 to 8 characters, with no control characters"
                case "ui.stopKeys": "is \"\(value)\": use \"esc\", \"ctrl-c\" or \"both\""
                case "compactAt": "is \(value): use \(CompactionThreshold.expected)"
                case "ui.queuedOnStop": "is \"\(value)\": use \"none\", \"next\" or \"all\""
                default: "is \"\(value)\": use \"workspace\", \"anywhere\" or a list of paths"
            }
        }
    }
}
