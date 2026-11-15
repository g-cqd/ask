internal import AemiJSON
package import AemiJSONRPC
internal import AemiRuntime
internal import Foundation
internal import Synchronization

/// The process that hosts a script's VM (ADR-0156): `ask codemode`, a child of the ask that runs the tools. It is asked to run
/// one script, asks its parent for each tool the script calls, and answers with what the script came to. It is a process of
/// its own so that a script which never yields, or takes all the memory, is ended by ending the process.
package final class CodemodeHost: Sendable {
    /// The exit status of a host that ended itself for the memory it had taken.
    package static let memoryExit: Int32 = 86
    /// A tool may run for as long as the parent lets it: the script's deadline is the parent's to keep, not a call's.
    private static let patience: Duration = .seconds(7 * 24 * 3600)

    /// The connection to the parent, which is made after this and so given once it exists.
    private let parent = Mutex<JSONRPCConnection?>(nil)

    private init() {}

    /// Serves the parent whose bytes are `chunks`, writing to `sink`, until they end.
    package static func serve(reading chunks: some AsyncSequence<[UInt8], any Error>, writing sink: any JSONRPCSink)
        async
    {
        let host = CodemodeHost()
        let connection = JSONRPCConnection(serving: sink, framing: .lines) { request in host.admit(request) }
        host.parent.withLock { $0 = connection }
        await connection.run(reading: chunks)
    }

    /// Serves the parent on the process's standard streams, and ends the process when it has gone or when the host has taken
    /// more than `memoryLimit` bytes.
    package static func serveStandardStreams(memoryLimit: Int) async {
        CodemodeMemory.watch(limit: memoryLimit) { exit(memoryExit) }
        let reader = BlockingOffloadPool(width: 1)
        let (chunks, feed) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        Task {
            // try?: the parent's bytes ending and failing mean the same here: it has gone
            _ = try? await {
                for try await chunk in FileDescriptorChunks(descriptor: STDIN_FILENO, pool: reader) {
                    feed.yield(chunk)
                }
            }()
            // The parent has gone, or has what it asked for: a script still running has nobody to answer.
            exit(0)
        }
        await serve(reading: chunks, writing: CodemodeOutput())
    }

    private func admit(_ request: JSONRPCRequest) -> JSONRPCConnection.RequestWork {
        guard request.method == CodemodeWire.run else {
            return {
                .failure(
                    JSONRPCError(code: JSONRPCError.methodNotFound, message: "Method not found: \(request.method)")
                )
            }
        }
        guard let run = CodemodeWire.run(from: request.params) else {
            return { .failure(JSONRPCError(code: JSONRPCError.invalidParams, message: "run needs code and tools")) }
        }
        return {
            let result = await CodemodeVM.run(run.code, tools: run.tools) { tool, arguments in
                await self.call(tool, arguments)
            }
            return .success(CodemodeWire.encoded(result))
        }
    }

    /// Asks the parent to call `tool`: its text, or why it failed.
    private func call(_ tool: String, _ arguments: String) async -> Result<String, CodemodeCallFailure> {
        guard let parent = parent.withLock({ $0 }) else {
            return .failure(CodemodeCallFailure("ask is not there to call \(tool)."))
        }
        do {
            let parameters = CodemodeWire.callParameters(tool: tool, arguments: arguments)
            let answer = try await parent.request(CodemodeWire.call, parameters, timeout: Self.patience)
            return CodemodeWire.answerText(from: answer).map(Result.success)
                ?? .failure(CodemodeCallFailure("ask answered \(tool) with something that is not text."))
        } catch JSONRPCConnectionError.response(let refused) {
            // The tool's own words: what a script catches is what a direct call would have returned as its error.
            return .failure(CodemodeCallFailure(refused.message))
        } catch {
            return .failure(CodemodeCallFailure("The call of \(tool) got no answer: \(error)"))
        }
    }
}
