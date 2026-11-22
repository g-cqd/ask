internal import AskCore

extension ConfigurationFile {
    /// A limit: a whole number, `least` or more, or `null` for none (`ui.pathAncestors`, roadmap 0215; `ui.historyLimit`, note n29),
    /// which both read as -1 (``UISection/noAncestorLimit``, ``UISection/noHistoryLimit``).
    static func decodeCount(_ container: KeyedDecodingContainer<Key>, key: Key, named name: String, least: Int) throws
        -> Int
    {
        if try container.decodeNil(forKey: key) { return -1 }
        let count = try container.decode(Int.self, forKey: key)
        guard count >= least else { throw BadValue(key: name, shown: String(count)) }
        return count
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
