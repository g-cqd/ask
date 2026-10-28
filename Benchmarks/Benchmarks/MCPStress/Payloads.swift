import AemiJSON

/// The messages every case exchanges: a `tools/call` for `echo` with a reply of `size` bytes of text, so cases differ only in how the bytes
/// travel and who reads them.
enum Payloads {
    /// Reply sizes: a tiny answer, a page, and a large file's worth.
    static let sizes = [2, 4096, 262_144]

    /// `{"content":[{"type":"text","text":"xx…"}],"isError":false}`
    static func result(size: Int) -> String {
        #"{"content":[{"type":"text","text":""# + String(repeating: "x", count: size) + #""}],"isError":false}"#
    }

    /// The whole answer line to request `id`.
    static func reply(id: Int, size: Int) -> [UInt8] {
        Array(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(result(size: size))}"#.utf8)
    }

    /// The tool's arguments, as the connection is given them.
    static func arguments(size: Int) -> [UInt8] { Array(#"{"size":\#(size)}"#.utf8) }

    /// A request written the least costly correct way: what any client must at least do to ask.
    static func request(id: Int, size: Int) -> [UInt8] {
        var writer = JSONStreamWriter(options: .rfc8259)
        writer.beginObject()
        writer.key("jsonrpc")
        writer.string("2.0")
        writer.key("id")
        writer.integer(id)
        writer.key("method")
        writer.string("tools/call")
        writer.key("params")
        writer.beginObject()
        writer.key("name")
        writer.string("echo")
        writer.key("arguments")
        writer.raw(arguments(size: size))
        writer.endObject()
        writer.endObject()
        return writer.finish()
    }

    /// The text of an answer line, read the least costly correct way: one parse, one string. Nil when it is not an answer.
    static func text(of line: [UInt8]) -> String? {
        guard let document = try? AemiJSON.parse(line) else { return nil }
        return document.root["result"]["content"][index: 0]["text"].string
    }
}
