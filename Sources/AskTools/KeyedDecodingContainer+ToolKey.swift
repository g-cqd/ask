internal import AskAgentCore

extension KeyedDecodingContainer where Key == RecordKey {
    /// Refuses a field outside `allowed`, naming it.
    func only(_ allowed: Set<String>, in place: String, for what: String) throws {
        if let extra = allKeys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
            throw ToolInputError(
                "\(place): \(what) takes no \"\(extra)\"; it takes \(allowed.sorted().joined(separator: ", "))."
            )
        }
    }

    func field<Value: Decodable>(_ name: String, _ type: Value.Type = Value.self) throws -> Value? {
        try decodeIfPresent(Value.self, forKey: RecordKey(name))
    }

    /// Ids as written, in one string: `t3 t5-t9 @1`.
    func refs(_ name: String, prefix: Character, in place: String) throws -> [ListRef]? {
        guard let text = try field(name, String.self) else { return nil }
        guard let refs = ListRef.list(text, prefix: prefix) else {
            throw ToolInputError(
                "\(place): \(name) \"\(text)\" holds what is not an id: \(prefix)3, \(prefix)5-\(prefix)9, or @1."
            )
        }
        return refs
    }

    /// Words, in one string: `a b`.
    func words(_ name: String) throws -> [String]? {
        try field(name, String.self).map { $0.split(separator: " ").map(String.init) }
    }
}
