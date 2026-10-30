extension UISection {
    /// The value of `key` as a configuration file writes it (`true`, `words`, `3`; free text in quotes), or nil when this section does not set it. The
    /// names are those of ``keys``, so `ask config` can show each key under the name a person types (roadmaps 0103 and 0154).
    public func value(forKey key: String) -> String? {
        let flag = Self.flag
        switch key {
            case "mouse": return flag(mouse)
            case "copyOnSelect": return flag(copyOnSelect)
            case "fold.tools": return flag(foldTools)
            case "fold.thinking": return flag(foldThinking)
            case "fold.code": return flag(foldCode)
            case "fold.codeLines": return codeFoldLines.map(String.init)
            case "scrollLines": return scrollLines.map(String.init)
            case "inputRows": return promptRows.map(String.init)
            case "sidebar": return sidebarOpen.map { $0 ? "open" : "closed" }
            case "inputPrefix": return prompt.map { "\"\($0)\"" }
            case "tint": return flag(tint)
            case "appearance": return appearance?.rawValue
            case "separator": return flag(separator)
            case "padding": return flag(padding)
            case "markdown": return flag(markdown)
            case "durations": return localizedDurations.map { $0 ? "words" : "clock" }
            case "spinner": return spinner?.rawValue
            case "showTimeout": return timeout?.rawValue
            case "timeoutLabel": return timeoutLabel.map { "\"\($0)\"" }
            default: return behaviorValue(forKey: key)
        }
    }

    private static func flag(_ value: Bool?) -> String? { value.map { $0 ? "true" : "false" } }

    private func behaviorValue(forKey key: String) -> String? {
        switch key {
            case "leaveFinishedJob": return Self.flag(jobAutoReturnWhenFocused)
            case "stopKeys": return interruptKeys?.rawValue
            case "stopTwice":
                guard escapeInterruptRequiresConfirmation != nil || abortTurnRequiresConfirmation != nil else {
                    return nil
                }
                let keys = [
                    ("esc", escapeInterruptRequiresConfirmation ?? true),
                    ("ctrl-c", abortTurnRequiresConfirmation ?? false)
                ]
                let pressedTwice = keys.filter(\.1).map(\.0)
                return pressedTwice.isEmpty ? "none" : pressedTwice.joined(separator: ", ")
            case "queuedOnStop": return interruptSendsQueued?.rawValue
            case "listAllModels": return Self.flag(onlyUsefulModels.map { !$0 })
            default: return nil
        }
    }
}
