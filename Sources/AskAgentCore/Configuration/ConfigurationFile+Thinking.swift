internal import AskAI

extension ConfigurationFile {
    static func decodeThinking(_ container: KeyedDecodingContainer<Key>, key: Key) throws -> ThinkingLevel {
        let name = try container.decode(String.self, forKey: key)
        guard let level = ThinkingLevel(rawValue: name) else { throw BadValue(key: "thinking", value: name) }
        return level
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
