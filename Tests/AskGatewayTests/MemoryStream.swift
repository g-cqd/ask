internal import Synchronization

@testable import AskGateway

/// Two ends of an in-memory byte stream, for testing what runs over one: what one end sends, the other receives, in pieces as sent.
actor MemoryStream: ByteStream {
    private var iterator: AsyncStream<[UInt8]>.Iterator
    private let outgoing: AsyncStream<[UInt8]>.Continuation
    private let closer: AsyncStream<[UInt8]>.Continuation
    /// Every piece sent, for a test that looks at what crossed the wire.
    nonisolated let sent = Mutex<[[UInt8]]>([])

    private init(
        incoming: AsyncStream<[UInt8]>,
        outgoing: AsyncStream<[UInt8]>.Continuation,
        closer: AsyncStream<[UInt8]>.Continuation
    ) {
        iterator = incoming.makeAsyncIterator()
        self.outgoing = outgoing
        self.closer = closer
    }

    /// A connected pair.
    static func pair() -> (MemoryStream, MemoryStream) {
        let (aToB, aSends) = AsyncStream<[UInt8]>.makeStream()
        let (bToA, bSends) = AsyncStream<[UInt8]>.makeStream()
        return (
            MemoryStream(incoming: bToA, outgoing: aSends, closer: bSends),
            MemoryStream(incoming: aToB, outgoing: bSends, closer: aSends)
        )
    }

    func send(_ bytes: [UInt8]) async throws {
        sent.withLock { $0.append(bytes) }
        outgoing.yield(bytes)
    }

    /// One task receives at a time, as a link does.
    func receive() async throws -> [UInt8]? {
        var current = iterator
        let next = await current.next(isolation: self)
        iterator = current
        return next
    }

    func close() async {
        outgoing.finish()
        closer.finish()
    }
}
