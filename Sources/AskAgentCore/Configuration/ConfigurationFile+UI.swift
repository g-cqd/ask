extension ConfigurationFile {
    /// The `ui` keys the screen implements; unknown keys are refused.
    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    struct UIDecoded: Decodable {
        var section = UISection()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    // @dl:accept -- the key tables are the data, and the walk over them is already shared
                    case "mouse": section.mouse = try container.decode(Bool.self, forKey: key)
                    // @dl:accept -- typed key tables are data; their decoding walk is already shared
                    case "copyOnSelect": section.copyOnSelect = try container.decode(Bool.self, forKey: key)
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
                    case "tint", "separator", "padding", "localizedDurations":
                        let name = try container.decode(String.self, forKey: key)
                        guard name == "on" || name == "off" else {
                            throw BadValue(key: "ui." + key.stringValue, value: name)
                        }
                        switch key.stringValue {
                            case "tint": section.tint = name == "on"
                            case "separator": section.separator = name == "on"
                            case "padding": section.padding = name == "on"
                            default: section.localizedDurations = name == "on"
                        }
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
}
