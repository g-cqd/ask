internal import AemiJSON

/// The messages this client writes.
enum MCPWire {
    /// A request.
    static func request(id: Int, method: String, params: [UInt8]?) -> [UInt8] {
        message { writer in
            put(&writer, "id", integer: id)
            put(&writer, "method", string: method)
            if let params { put(&writer, "params", raw: params) }
        }
    }

    /// A notification: no id, and no answer.
    static func notification(method: String, params: [UInt8]? = nil) -> [UInt8] {
        message { writer in
            put(&writer, "method", string: method)
            if let params { put(&writer, "params", raw: params) }
        }
    }

    /// The answer to a request from the server, echoing its id as it was written.
    static func result(id: [UInt8], _ result: String = "{}") -> [UInt8] {
        message { writer in
            put(&writer, "id", raw: id)
            put(&writer, "result", raw: Array(result.utf8))
        }
    }

    /// A refusal of a request from the server.
    static func failure(id: [UInt8], code: Int, message text: String) -> [UInt8] {
        message { writer in
            put(&writer, "id", raw: id)
            writer.key("error")
            object(&writer) { error in
                put(&error, "code", integer: code)
                put(&error, "message", string: text)
            }
        }
    }

    /// `{"requestId": id, "reason": reason}`, the notice that a request is abandoned.
    static func cancelledParams(id: Int, reason: String) -> [UInt8] {
        var writer = JSONStreamWriter(options: .rfc8259)
        object(&writer) { body in
            put(&body, "requestId", integer: id)
            put(&body, "reason", string: reason)
        }
        return writer.finish()
    }

    /// A JSON-RPC message: the version, then what `fields` writes.
    private static func message(_ fields: (inout JSONStreamWriter) -> Void) -> [UInt8] {
        var writer = JSONStreamWriter(options: .rfc8259)
        object(&writer) { body in
            put(&body, "jsonrpc", string: "2.0")
            fields(&body)
        }
        return writer.finish()
    }

    /// An object around what `fields` writes.
    static func object(_ writer: inout JSONStreamWriter, _ fields: (inout JSONStreamWriter) -> Void) {
        writer.beginObject()
        fields(&writer)
        writer.endObject()
    }

    /// A member whose value is a string.
    static func put(_ writer: inout JSONStreamWriter, _ key: String, string: String) {
        writer.key(key)
        writer.string(string)
    }

    /// A member whose value is an integer.
    static func put(_ writer: inout JSONStreamWriter, _ key: String, integer: Int) {
        writer.key(key)
        writer.integer(integer)
    }

    /// A member whose value is JSON already written.
    static func put(_ writer: inout JSONStreamWriter, _ key: String, raw: [UInt8]) {
        writer.key(key)
        writer.raw(raw)
    }
}
