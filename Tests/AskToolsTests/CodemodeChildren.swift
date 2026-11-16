import AemiJSONRPC
import AskCodemode
import Synchronization

@testable import AskTools

/// Children for a keeper under test: the real host, run in this process over streams; one that never answers; one that says
/// things and never ends; one that is gone, with the exit status it left.
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

    /// A child that, given its script, says `items`, then calls `read`, and never ends.
    static func saying(_ items: [CodemodeItem]) -> CodemodeChild.Start {
        { _ in
            let (incoming, lines) = AsyncStream<[UInt8]>.makeStream()
            let asked = Mutex(false)
            return CodemodeChild(
                incoming: incoming,
                send: { _ in
                    // Its script is the first thing it is sent; what comes after is the answer to its call.
                    guard
                        !asked.withLock({ was in
                            defer { was = true }
                            return was
                        })
                    else { return }
                    for item in items {
                        lines.yield(
                            try JSONRPC.notification(
                                method: CodemodeWire.said,
                                params: CodemodeWire.saidParameters(item)
                            )
                        )
                    }
                    let call = CodemodeWire.callParameters(tool: "read", arguments: "{}")
                    lines.yield(try JSONRPC.request(id: .number(1), method: CodemodeWire.call, params: call))
                },
                close: {
                    lines.finish()
                    return nil
                }
            )
        }
    }
}
