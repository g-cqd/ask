extension ConfigurationFile {
    /// The `ui` keys the screen implements; unknown keys are refused.
    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    struct UIDecoded: Decodable {
        var section = UISection()

        /// `ui.interruptKeys` and `ui.interruptSendsQueued`: one word out of a short list.
        private mutating func decodeInterruptChoice(
            _ key: Key, from container: KeyedDecodingContainer<Key>
        ) throws {
            let raw = try container.decode(String.self, forKey: key)
            if key.stringValue == "interruptKeys" {
                guard let keys = InterruptKeysPreference(rawValue: raw) else {
                    throw BadValue(key: "ui.interruptKeys", value: raw)
                }
                section.interruptKeys = keys
            } else {
                guard let queued = QueuedAfterInterruptPreference(rawValue: raw) else {
                    throw BadValue(key: "ui.interruptSendsQueued", value: raw)
                }
                section.interruptSendsQueued = queued
            }
        }

        // @dl:accept -- the key walk is shared; each section names its own keys
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    // @dl:accept -- typed key tables decoded by the shared walk; the keys are the data
                    case "scrollLines": section.scrollLines = try container.decode(Int.self, forKey: key)
                    case "promptRows": section.promptRows = try container.decode(Int.self, forKey: key)
                    case "codeFoldLines": section.codeFoldLines = try container.decode(Int.self, forKey: key)
                    case "sidebar":
                        let name = try container.decode(String.self, forKey: key)
                        guard name == "open" || name == "closed" else {
                            throw BadValue(key: "ui.sidebar", value: name)
                        }
                        section.sidebarOpen = name == "open"
                    case "prompt": section.prompt = try container.decode(String.self, forKey: key)
                    case "spinner":
                        let raw = try container.decode(String.self, forKey: key)
                        guard let preference = SpinnerPreference(rawValue: raw) else {
                            throw BadValue(key: "ui.spinner", value: raw)
                        }
                        section.spinner = preference
                    // @dl:accept -- on/off keys decoded like the folded/open ones beside them; the key tables are the data
                    case "mouse", "copyOnSelect", "tint", "separator", "padding", "localizedDurations",
                        "jobAutoReturnWhenFocused",
                        // @dl:accept -- a key table decoded by the shared walk; the keys are the data
                        "abortTurnRequiresConfirmation",
                        "escapeInterruptRequiresConfirmation", "onlyUsefulModels":
                        let on = try ConfigurationFile.decodeSwitch(container, key: key, name: "ui." + key.stringValue)
                        let name = on ? "on" : "off"
                        switch key.stringValue {
                            case "mouse": section.mouse = on
                            case "copyOnSelect": section.copyOnSelect = on
                            case "tint": section.tint = name == "on"
                            case "separator": section.separator = name == "on"
                            case "padding": section.padding = name == "on"
                            case "localizedDurations": section.localizedDurations = name == "on"
                            case "jobAutoReturnWhenFocused": section.jobAutoReturnWhenFocused = name == "on"
                            case "abortTurnRequiresConfirmation": section.abortTurnRequiresConfirmation = name == "on"
                            case "onlyUsefulModels": section.onlyUsefulModels = name == "on"
                            default: section.escapeInterruptRequiresConfirmation = name == "on"
                        }
                    case "interruptKeys", "interruptSendsQueued":
                        try decodeInterruptChoice(key, from: container)
                    // @dl:accept -- a key table decoded by the shared walk; the keys are the data
                    case "tools", "thinking", "code":
                        let name = try container.decode(String.self, forKey: key)
                        guard name == "folded" || name == "open" else {
                            throw BadValue(key: "ui." + key.stringValue, value: name)
                        }
                        switch key.stringValue {
                            case "tools": section.foldTools = name == "folded"
                            case "thinking": section.foldThinking = name == "folded"
                            default: section.foldCode = name == "folded"
                        }
                    default: throw UnknownKey(key: "ui." + key.stringValue)
                }
            }
        }
    }

    /// An on/off setting: `"on"` or `"off"`, or `true` or `false`, so neither way of writing it is an error.
    static func decodeSwitch(_ container: KeyedDecodingContainer<Key>, key: Key, name: String) throws -> Bool {
        if let flag = try? container.decode(Bool.self, forKey: key) { return flag }
        let word = try container.decode(String.self, forKey: key)
        guard word == "on" || word == "off" else { throw BadValue(key: name, value: word) }
        return word == "on"
    }
}
