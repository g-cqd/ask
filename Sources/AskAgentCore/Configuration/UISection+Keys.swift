extension UISection {
    /// The value of `key` as a configuration file writes it (`"on"`, `"folded"`, `3`), or nil when this section does not set it. The names
    /// are those of ``keys``, so `ask config` can show each key under the name a person types (roadmap 0103).
    public func value(forKey key: String) -> String? {
        let onOff = Self.onOff
        func fold(_ value: Bool?) -> String? { value.map { $0 ? "folded" : "open" } }
        switch key {
            case "mouse": return onOff(mouse)
            case "copyOnSelect": return onOff(copyOnSelect)
            case "tools": return fold(foldTools)
            case "thinking": return fold(foldThinking)
            case "scrollLines": return scrollLines.map(String.init)
            case "promptRows": return promptRows.map(String.init)
            case "code": return fold(foldCode)
            case "codeFoldLines": return codeFoldLines.map(String.init)
            case "sidebar": return sidebarOpen.map { $0 ? "open" : "closed" }
            case "prompt": return prompt.map { $0.isEmpty ? "none" : "\"\($0)\"" }
            case "tint": return onOff(tint)
            case "appearance": return appearance?.rawValue
            case "separator": return onOff(separator)
            case "padding": return onOff(padding)
            case "markdown": return onOff(markdown)
            case "localizedDurations": return onOff(localizedDurations)
            case "spinner": return spinner?.rawValue
            case "timeout": return timeout?.rawValue
            case "timeoutLabel": return timeoutLabel.map { "\"\($0)\"" }
            default: return behaviorValue(forKey: key)
        }
    }

    private static func onOff(_ value: Bool?) -> String? { value.map { $0 ? "on" : "off" } }

    private func behaviorValue(forKey key: String) -> String? {
        let onOff = Self.onOff
        switch key {
            case "jobAutoReturnWhenFocused": return onOff(jobAutoReturnWhenFocused)
            case "abortTurnRequiresConfirmation": return onOff(abortTurnRequiresConfirmation)
            case "interruptKeys": return interruptKeys?.rawValue
            case "escapeInterruptRequiresConfirmation": return onOff(escapeInterruptRequiresConfirmation)
            case "interruptSendsQueued": return interruptSendsQueued?.rawValue
            case "onlyUsefulModels": return onOff(onlyUsefulModels)
            default: return nil
        }
    }
}
