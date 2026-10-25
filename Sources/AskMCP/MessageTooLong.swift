/// A server sent a message longer than the transport allows.
struct MessageTooLong: Error, CustomStringConvertible {
    let limit: Int
    var description: String { "the server sent a message longer than \(limit) bytes" }
}
