import AemiJSON
import AemiJSONRPC
import Synchronization
import Testing

@testable import AskCodemode

/// The host, in this process and over pipes that are streams: asked to run a script, it asks back for each tool the script
/// calls, and answers with what the script came to.
@Suite("The host runs a script for its parent, and asks the parent for each tool", .timeLimit(.minutes(1)))
struct CodemodeHostTests {
    /// A parent of a host: what the host writes is this side's input, and the other way round.
    private final class Parent: JSONRPCSink, Sendable {
        let toHost = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        let fromHost = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        let calls = Mutex<[String]>([])

        func write(_ bytes: [UInt8]) async throws { toHost.continuation.yield(bytes) }

        /// Runs `code` in a host; the parent answers `read` and refuses anything else.
        func run(_ code: String, tools: [CodemodeCallable]) async throws -> JSON {
            let connection = JSONRPCConnection(serving: self, framing: .lines) { [self] request in
                let call = CodemodeWire.call(from: request.params)
                calls.withLock { $0.append("\(request.method) \(call?.tool ?? "?") \(call?.arguments ?? "?")") }
                return {
                    call?.tool == "read"
                        ? .success(CodemodeWire.answer("read \(call?.arguments ?? "")"))
                        : .failure(JSONRPCError(code: -32000, message: "No tool is named \(call?.tool ?? "?")."))
                }
            }
            let host = Task {
                await CodemodeHost.serve(reading: toHost.stream, writing: HostSink(to: fromHost.continuation))
            }
            let reading = Task { await connection.run(reading: fromHost.stream) }
            defer {
                toHost.continuation.finish()
                fromHost.continuation.finish()
                host.cancel()
                reading.cancel()
            }
            return try await connection.request(
                CodemodeWire.run,
                CodemodeWire.runParameters(code: code, tools: tools),
                timeout: .seconds(30)
            )
        }
    }

    private struct HostSink: JSONRPCSink {
        let to: AsyncThrowingStream<[UInt8], any Error>.Continuation
        func write(_ bytes: [UInt8]) async throws { to.yield(bytes) }
    }

    private let tools = [
        CodemodeCallable(name: "read", description: "Read."), CodemodeCallable(name: "gone", description: "Not there.")
    ]

    @Test func `a script's calls are asked of the parent, and its result comes back whole`() async throws {
        let parent = Parent()
        let answer = try await parent.run(
            #"const a = await tools.read({ path: "x" }); console.log("seen"); text(a); return a.length;"#,
            tools: tools
        )
        let expected = CodemodeResult(items: [
            CodemodeItem(text: "seen", console: true), CodemodeItem(text: #"read {"path":"x"}"#),
            CodemodeItem(text: "17")
        ])
        #expect(CodemodeWire.result(from: answer) == expected)
        #expect(parent.calls.withLock { $0 } == [#"call read {"path":"x"}"#])
    }

    @Test func `a call the parent refuses rejects with the parent's words`() async throws {
        let answer = try await Parent()
            .run("try { await tools.gone({}); } catch (e) { return e.message; }", tools: tools)
        #expect(CodemodeWire.result(from: answer)?.items.map(\.text) == ["No tool is named gone."])
    }

    @Test func `a script that fails is still an answer, with why and what it had said`() async throws {
        let answer = try await Parent().run("text('before'); tools.read({}); throw new Error('mine');", tools: tools)
        let expected = CodemodeResult(
            items: [CodemodeItem(text: "before")],
            failure: "Error: mine (codemode.js:1)",
            unsettled: 1
        )
        #expect(CodemodeWire.result(from: answer) == expected)
    }

    @Test func `anything but a run with a script is refused`() async {
        let parent = Parent()
        let connection = JSONRPCConnection(serving: parent, framing: .lines) { _ in { .success(true) } }
        let host = Task {
            await CodemodeHost.serve(reading: parent.toHost.stream, writing: HostSink(to: parent.fromHost.continuation))
        }
        let reading = Task { await connection.run(reading: parent.fromHost.stream) }
        await #expect(
            throws: JSONRPCConnectionError.response(JSONRPCError(code: -32601, message: "Method not found: stop"))
        ) {
            _ = try await connection.request("stop").string
        }
        await #expect(
            throws: JSONRPCConnectionError.response(JSONRPCError(code: -32602, message: "run needs code and tools"))
        ) {
            _ = try await connection.request("run", ["code": 7]).string
        }
        parent.toHost.continuation.finish()
        parent.fromHost.continuation.finish()
        host.cancel()
        reading.cancel()
    }

    @Test func `what crosses the wire reads back as it was written`() throws {
        let result = CodemodeResult(
            items: [CodemodeItem(text: "a\n\"b\"", console: true), CodemodeItem(text: "")],
            failure: "why",
            unsettled: 3
        )
        let bytes = try CodemodeWire.encoded(result).encodedBytes()
        #expect(CodemodeWire.result(from: try AemiJSON.parse(bytes).root) == result)
        let run = try CodemodeWire.runParameters(code: "return 1;", tools: tools).encodedBytes()
        let read = CodemodeWire.run(from: try AemiJSON.parse(run).root)
        #expect(read?.code == "return 1;" && read?.tools == tools)
    }

    @Test func `the footprint is what the process has dirtied, and grows with it`() {
        let before = CodemodeMemory.footprint()
        #expect(before > 1 << 20)
        var held = [UInt8](repeating: 1, count: 64 << 20)
        held[held.count - 1] = 2
        #expect(CodemodeMemory.footprint() - before > 48 << 20, "64 MiB written to")
        #expect(held.last == 2)
    }
}
