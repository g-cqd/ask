internal import AskAI

extension ConfigurationFile {
    /// A value the key does not take, refused with what the key takes, from the catalog (roadmap 0118).
    struct BadValue: Error {
        let key: String
        /// The value as the file wrote it: a string in quotes, a number as it is.
        let shown: String

        /// A string the key does not take.
        init(key: String, value: String) {
            self.key = key
            self.shown = "\"\(value)\""
        }

        /// A value already written as JSON (a number).
        init(key: String, shown: String) {
            self.key = key
            self.shown = shown
        }

        var reason: String {
            switch key {
                // The names roadmap 0154 replaced, refused under the name the file used.
                case "ui.tools", "ui.thinking", "ui.code": "is \(shown): use \"folded\" or \"open\""
                case "ui.localizedDurations", "ui.onlyUsefulModels", "ui.escapeInterruptRequiresConfirmation",
                    "ui.abortTurnRequiresConfirmation":
                    "is \(shown): use \"on\" or \"off\""
                case "ui.stopTwice": "names \(shown): use \"esc\" and \"ctrl-c\""
                default: "is \(shown): use \(SettingCatalog.setting(key)?.expected ?? "another value")"
            }
        }
    }
}
