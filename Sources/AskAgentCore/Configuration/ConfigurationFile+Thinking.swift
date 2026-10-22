internal import AskAI

extension ConfigurationFile {
    static func decodeThinking(_ container: KeyedDecodingContainer<Key>, key: Key) throws -> ThinkingLevel {
        let name = try container.decode(String.self, forKey: key)
        guard let level = ThinkingLevel(rawValue: name) else { throw BadValue(key: "thinking", value: name) }
        return level
    }
}
