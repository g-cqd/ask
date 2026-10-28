internal import AskAI

extension ConfigurationFile {
    /// A key whose value is one of `Choice`'s names (`thinking`, `keepAwake`); any other string is refused, naming the key.
    static func decodeChoice<Choice: RawRepresentable>(
        _ container: KeyedDecodingContainer<Key>, key: Key, as _: Choice.Type
    ) throws -> Choice where Choice.RawValue == String {
        let name = try container.decode(String.self, forKey: key)
        guard let choice = Choice(rawValue: name) else { throw BadValue(key: key.stringValue, value: name) }
        return choice
    }

    /// `maxTurns`: a whole number of at least 1, or `"none"` for no limit (roadmap 0098), kept as ``Configuration/noTurnLimit``.
    static func decodeMaxTurns(_ container: KeyedDecodingContainer<Key>, key: Key) throws -> Int {
        if let turns = try? container.decode(Int.self, forKey: key) { return turns }
        let text = try container.decode(String.self, forKey: key)
        guard let turns = Configuration.turnLimit(parsing: text) else {
            throw BadValue(key: "maxTurns", value: "\"\(text)\"")
        }
        return turns
    }

    /// `compactAt`: a whole number of tokens (`150000`, `0`) or a share of the window as a string (`"75%"`), roadmap 0104.
    static func decodeCompactAt(_ container: KeyedDecodingContainer<Key>, key: Key) throws -> CompactionThreshold {
        if let tokens = try? container.decode(Int.self, forKey: key) {
            guard tokens >= 0 else { throw BadValue(key: "compactAt", value: String(tokens)) }
            return .tokens(tokens)
        }
        let text = try container.decode(String.self, forKey: key)
        guard let threshold = CompactionThreshold(parsing: text), threshold.percent != nil else {
            throw BadValue(key: "compactAt", value: "\"\(text)\"")
        }
        return threshold
    }
}
