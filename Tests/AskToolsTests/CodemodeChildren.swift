import AemiJSONRPC
import AskCodemode

@testable import AskTools

/// Children for a keeper under test: the real host, run in this process over streams; one that never answers; one that is
/// gone, with the exit status it left.
enum CodemodeChildren {
    private struct Sink: JSONRPCSink {
        let lines: AsyncStream<[UInt8]>.Continuation
        func write(_ bytes: [UInt8]) async throws { lines.yield(bytes.last == 0x0A ? Array(bytes.dropLast()) : bytes) }
    }

    /// The host itself, hosting a real VM, with streams for pipes.
    static let inProcess: CodemodeChild.Start = { _ in
        let (toHost, feed) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        let (fromHost, lines) = AsyncStream<[UInt8]>.makeStream()
        let host = Task { await CodemodeHost.serve(reading: toHost, writing: Sink(lines: lines)) }
        return CodemodeChild(
            incoming: fromHost,
            send: { feed.yield($0 + [0x0A]) },
            close: {
                feed.finish()
                lines.finish()
                host.cancel()
                return 0
            }
        )
    }

    /// A child that takes what it is sent and says nothing: a script that never ends.
    static let silent: CodemodeChild.Start = { _ in
        let (incoming, lines) = AsyncStream<[UInt8]>.makeStream()
        return CodemodeChild(
            incoming: incoming,
            send: { _ in },
            close: {
                lines.finish()
                return nil
            }
        )
    }

    /// A child that is gone as soon as it is spoken to, having exited with `status`.
    static func gone(exit status: Int32) -> CodemodeChild.Start {
        { _ in
            let (incoming, lines) = AsyncStream<[UInt8]>.makeStream()
            return CodemodeChild(incoming: incoming, send: { _ in lines.finish() }, close: { status })
        }
    }
}
