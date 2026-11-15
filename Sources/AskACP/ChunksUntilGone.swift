/// A client's bytes, with something done once they have ended: at the end of its input a client has gone, whether it closed its
/// side or died, and what still runs for it has nobody to answer.
struct ChunksUntilGone<Base: AsyncSequence<[UInt8], any Error>>: AsyncSequence {
    let base: Base
    /// Called once, when the bytes have ended or reading them failed.
    let gone: @Sendable () -> Void

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        let gone: @Sendable () -> Void

        mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws -> [UInt8]? {
            let chunk: [UInt8]?
            do { chunk = try await base.next(isolation: actor) } catch {
                gone()
                throw error
            }
            if chunk == nil { gone() }
            return chunk
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(base: base.makeAsyncIterator(), gone: gone) }
}
