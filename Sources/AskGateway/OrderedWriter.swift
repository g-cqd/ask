/// Writes sealed messages to a stream in the order they were queued, one at a time (``NoiseLink``): two sends at once must reach the
/// wire in the order their nonces were used.
enum OrderedWriter {
    /// The task that writes `queue` to `stream`. It holds the stream and the queue, never the link: the queue ends when the link is
    /// closed or let go, and the task with it; a write that fails closes the stream and ends the task.
    static func start(_ queue: AsyncStream<[UInt8]>, to stream: any ByteStream) -> Task<Void, Never> {
        Task {
            for await bytes in queue {
                do { try await stream.send(bytes) } catch {
                    await stream.close()
                    return
                }
            }
        }
    }
}
