extension ConfigurationFile {
    /// The `ui` object: four keys, and nothing else.
    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    struct UIDecoded: Decodable {
        var section = UISection()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    // @dl:accept -- the key tables are the data, and the walk over them is already shared
                    case "mouse": section.mouse = try container.decode(Bool.self, forKey: key)
                    case "copyOnSelect": section.copyOnSelect = try container.decode(Bool.self, forKey: key)
                    case "scrollLines": section.scrollLines = try container.decode(Int.self, forKey: key)
                    case "tools":
                        let name = try container.decode(String.self, forKey: key)
                        guard name == "folded" || name == "open" else { throw BadValue(key: "ui.tools", value: name) }
                        section.foldTools = name == "folded"
                    default: throw UnknownKey(key: "ui." + key.stringValue)
                }
            }
        }
    }
}
