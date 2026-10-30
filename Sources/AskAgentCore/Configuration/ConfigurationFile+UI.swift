extension ConfigurationFile {
    /// The `ui` keys the screen implements, under the names roadmap 0154 settled (``SettingRenames`` reads the old ones); unknown keys
    /// are refused.
    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    struct UIDecoded: Decodable {
        var section = UISection()

        // @dl:accept -- the key walk is shared; each section names its own keys
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                let name = "ui." + key.stringValue
                // @dl:accept -- the key walk is shared; each section names its own keys
                switch key.stringValue {
                    case "scrollLines": section.scrollLines = try container.decode(Int.self, forKey: key)
                    case "inputRows": section.promptRows = try container.decode(Int.self, forKey: key)
                    case "inputPrefix": section.prompt = try container.decode(String.self, forKey: key)
                    case "fold": try decodeFold(container.decode(FoldDecoded.self, forKey: key))
                    case "sidebar":
                        section.sidebarOpen =
                            try ConfigurationFile.word(container, key, name, ["open", "closed"]) == "open"
                    case "durations":
                        section.localizedDurations =
                            try ConfigurationFile.word(container, key, name, ["words", "clock"]) == "words"
                    case "stopTwice": try decodeStopTwice(container.decode([String].self, forKey: key))
                    case "mouse", "copyOnSelect", "tint", "separator", "padding", "markdown", "leaveFinishedJob",
                        "listAllModels":
                        decodeSwitch(
                            key.stringValue, try ConfigurationFile.decodeSwitch(container, key: key, name: name))
                    default: try decodeChoice(key, from: container)
                }
            }
        }

        /// The keys whose value is one word of an enumeration, and the timeout's label.
        private mutating func decodeChoice(_ key: Key, from container: KeyedDecodingContainer<Key>) throws {
            let name = "ui." + key.stringValue
            switch key.stringValue {
                // @dl:accept -- one decode per choice key, each naming its own enumeration; the rows are data
                case "appearance":
                    section.appearance = try ConfigurationFile.decodeChoice(
                        container, key: key, as: AppearancePreference.self, named: name)
                case "spinner":
                    section.spinner = try ConfigurationFile.decodeChoice(
                        container, key: key, as: SpinnerPreference.self, named: name)
                case "stopKeys":
                    section.interruptKeys = try ConfigurationFile.decodeChoice(
                        container, key: key, as: InterruptKeysPreference.self, named: name)
                case "queuedOnStop":
                    section.interruptSendsQueued = try ConfigurationFile.decodeChoice(
                        container, key: key, as: QueuedAfterInterruptPreference.self, named: name)
                case "showTimeout":
                    section.timeout = try ConfigurationFile.decodeChoice(
                        container, key: key, as: TimeoutPreference.self, named: name)
                case "timeoutLabel":
                    section.timeoutLabel = try ConfigurationFile.decodeLabel(container, key: key, named: name)
                default: throw UnknownKey(key: name)
            }
        }

        private mutating func decodeSwitch(_ key: String, _ on: Bool) {
            switch key {
                case "mouse": section.mouse = on
                case "copyOnSelect": section.copyOnSelect = on
                case "tint": section.tint = on
                case "separator": section.separator = on
                case "padding": section.padding = on
                case "markdown": section.markdown = on
                case "leaveFinishedJob": section.jobAutoReturnWhenFocused = on
                default: section.onlyUsefulModels = !on  // listAllModels
            }
        }

        private mutating func decodeFold(_ fold: FoldDecoded) {
            section.foldTools = fold.tools
            section.foldThinking = fold.thinking
            section.foldCode = fold.code
            section.codeFoldLines = fold.codeLines
        }

        /// `ui.stopTwice`: the keys that must be pressed twice to stop a turn, `"esc"` and `"ctrl-c"`.
        private mutating func decodeStopTwice(_ keys: [String]) throws {
            for key in keys where key != "esc" && key != "ctrl-c" { throw BadValue(key: "ui.stopTwice", value: key) }
            section.escapeInterruptRequiresConfirmation = keys.contains("esc")
            section.abortTurnRequiresConfirmation = keys.contains("ctrl-c")
        }
    }

    /// `ui.fold`: which blocks start folded, and how many lines make a code block long.
    struct FoldDecoded: Decodable {
        var tools: Bool?
        var thinking: Bool?
        var code: Bool?
        var codeLines: Int?

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                let name = "ui.fold." + key.stringValue
                switch key.stringValue {
                    case "tools": tools = try ConfigurationFile.decodeSwitch(container, key: key, name: name)
                    case "thinking": thinking = try ConfigurationFile.decodeSwitch(container, key: key, name: name)
                    case "code": code = try ConfigurationFile.decodeSwitch(container, key: key, name: name)
                    case "codeLines": codeLines = try container.decode(Int.self, forKey: key)
                    default: throw UnknownKey(key: name)
                }
            }
        }
    }

    /// An on/off setting: `true` or `false`, or `"on"` or `"off"`, so neither way of writing it is an error.
    static func decodeSwitch(_ container: KeyedDecodingContainer<Key>, key: Key, name: String) throws -> Bool {
        if let flag = try? container.decode(Bool.self, forKey: key) { return flag }
        let word = try container.decode(String.self, forKey: key)
        guard word == "on" || word == "off" else { throw BadValue(key: name, value: word) }
        return word == "on"
    }

    /// One of `words`, under `name` in an error.
    static func word(_ container: KeyedDecodingContainer<Key>, _ key: Key, _ name: String, _ words: [String]) throws
        -> String
    {
        let word = try container.decode(String.self, forKey: key)
        guard words.contains(word) else { throw BadValue(key: name, value: word) }
        return word
    }
}
