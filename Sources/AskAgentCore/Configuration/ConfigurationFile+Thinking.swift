internal import AskAI

extension ConfigurationFile {
    static func decodeThinking(_ container: KeyedDecodingContainer<Key>, key: Key) throws -> ThinkingLevel {
        let name = try container.decode(String.self, forKey: key)
        guard let level = ThinkingLevel(rawValue: name) else { throw BadValue(key: "thinking", value: name) }
        return level
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
