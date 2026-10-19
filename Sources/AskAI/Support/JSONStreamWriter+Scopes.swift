internal import AemiJSON

/// Scoped writing, so a container cannot be opened and forgotten.
///
/// `beginObject()` and `endObject()` are a pair the compiler cannot see, and the encoders repeated them, with
/// `into: &writer` threaded through every helper. A closure gives the pairing a body and makes the structure of
/// the JSON the structure of the code, the way `withUnsafeBytes` and `withTaskGroup` scope their resource.
extension JSONStreamWriter {
    /// Writes one object whose members `body` writes.
    mutating func object(_ body: (inout JSONStreamWriter) -> Void) {
        beginObject()
        body(&self)
        endObject()
    }

    /// Writes one array whose elements `body` writes.
    mutating func array(_ body: (inout JSONStreamWriter) -> Void) {
        beginArray()
        body(&self)
        endArray()
    }

    /// Writes `key` with a string value.
    mutating func field(_ key: String, _ value: String) {
        self.key(key)
        string(value)
    }

    /// Writes `key` with a boolean value.
    mutating func field(_ key: String, _ value: Bool) {
        self.key(key)
        bool(value)
    }

    /// Writes `key` with an integer value.
    mutating func field(_ key: String, _ value: Int) {
        self.key(key)
        integer(value)
    }

    /// Writes an object that says what it is with `"type"` and carries one more string member, the shape of
    /// a text block and of a redacted-thinking block.
    mutating func typed(_ type: String, _ key: String, _ value: String) {
        object {
            $0.field("type", type)
            $0.field(key, value)
        }
    }

    /// The body of a streaming model request: one object that opens with `model`, `max_tokens` and `"stream": true`,
    /// the fields every provider's protocol shares, followed by what `rest` writes.
    static func streamingRequest(model: String, maxTokens: Int, _ rest: (inout JSONStreamWriter) -> Void) -> [UInt8] {
        var writer = JSONStreamWriter(capacity: 4_096)
        writer.object { writer in
            writer.field("model", model)
            writer.field("max_tokens", maxTokens)
            writer.field("stream", true)
            rest(&writer)
        }
        return writer.finish()
    }
}
