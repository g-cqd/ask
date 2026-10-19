internal import AemiJSON

extension JSONStreamWriter {
    /// A JSON object whose fields are all strings, in the order given: the shape of every sign-in and token request.
    static func object(of fields: [(String, String)]) -> [UInt8] {
        var writer = JSONStreamWriter()
        writer.beginObject()
        for (key, value) in fields {
            writer.key(key)
            writer.string(value)
        }
        writer.endObject()
        return writer.finish()
    }
}
