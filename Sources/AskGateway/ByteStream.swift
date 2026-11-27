/// A reliable, ordered byte stream, such as a TCP connection: what a ``NoiseLink`` runs over.
package protocol ByteStream: Sendable {
    /// Sends `bytes`, in order after what was sent before.
    func send(_ bytes: [UInt8]) async throws
    /// The next bytes that arrived, in any pieces; nil once the stream has ended.
    func receive() async throws -> [UInt8]?
    /// Ends the stream.
    func close() async
}
