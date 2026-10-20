internal import AemiJSON

/// Known credential records and verbatim, validated JSON for records a newer ask may understand.
///
/// Unknown values are not materialized as numbers: a large integer id or high-precision decimal must not be rounded
/// just because an unrelated provider signed in. Only the envelope's keys are re-emitted; unknown subtrees stay exact.
struct StoredCredentials: Codable {
    enum FormatError: Error { case newerVersion }
    var claude: ClaudeCredentials?
    var keys: [String: StoredKey]?
    var codex: CodexCredentials?
    var connection: ConnectionRecord?
    private var unknown: [String: [UInt8]] = [:]

    private enum CodingKeys: String, CodingKey {
        case claude, keys, codex, connection
    }

    init() {}

    init(decoding bytes: [UInt8]) throws {
        let document = try AemiJSON.parse(bytes, options: JSONParseOptions(recordsContainerSpans: true))
        if let version = document.root["connection"]["schemaVersion"].int, version != 1 {
            throw FormatError.newerVersion
        }
        self = try AemiJSON.JSONDecoder().decode(Self.self, from: document)
        var unavailable = false
        document.root.forEachMember { name, value in
            guard CodingKeys(rawValue: name) == nil else { return }
            if let raw = value.withRawJSONBytes({ Array($0) }) { unknown[name] = raw } else { unavailable = true }
        }
        guard !unavailable else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "An unknown record has no source span"))
        }
    }

    /// Encodes owned records, splicing every unknown value from its validated source bytes.
    func encoded() throws -> [UInt8] {
        let encoder = AemiJSON.JSONEncoder()
        var values = unknown
        values["claude"] = try claude.map { try encoder.encodeToBytes($0) }
        values["keys"] = try keys.map { try encoder.encodeToBytes($0) }
        values["codex"] = try codex.map { try encoder.encodeToBytes($0) }
        values["connection"] = try connection.map { try encoder.encodeToBytes($0) }
        var writer = JSONStreamWriter(options: .rfc8259)
        writer.beginObject()
        for name in values.keys.sorted() {
            guard let bytes = values[name] else { continue }
            writer.key(name)
            // These bytes came from the strict parser's recorded span, or the typed encoder above.
            writer.raw(bytes)
        }
        writer.endObject()
        return writer.finish()
    }
}
