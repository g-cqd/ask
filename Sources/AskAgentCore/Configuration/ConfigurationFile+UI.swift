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
                    case "scrollLines": section.scrollLines = try container.decode(Int.self, forKey: key)
                    case "promptRows": section.promptRows = try container.decode(Int.self, forKey: key)
                    case "tools", "thinking":
                        let name = try container.decode(String.self, forKey: key)
                        guard name == "folded" || name == "open" else {
                            throw BadValue(key: "ui." + key.stringValue, value: name)
                        }
                        if key.stringValue == "tools" {
                            section.foldTools = name == "folded"
                        } else {
                            section.foldThinking = name == "folded"
                        }
                    default: throw UnknownKey(key: "ui." + key.stringValue)
                }
            }
        }
    }
}
