import AemiJSON
import AemiJSONRPC
import AskCodemode
import Synchronization
import Testing

@testable import AskTools

/// The calls one script makes, as its keeper serves them (ADR-0156): a script may ask for a thousand at once; no more than
/// the limit run, and the others wait their turn.
@Suite("No more of a script's calls run at once than the limit", .timeLimit(.minutes(1)))
struct CodemodeCallsTests {
    private func request(_ id: Int, tool: String = "read") throws -> JSONRPCRequest {
        let body = try JSONRPC.request(
            id: .number(Int64(id)),
            method: CodemodeWire.call,
            params: CodemodeWire.callParameters(tool: tool, arguments: "{}")
        )
        guard case .request(let request) = try JSONRPCMessage(parsing: body) else {
            throw CodemodeCallFailure("not a request")
        }
        return request
    }

    @Test func `four run, the others wait, and each is run in the end`() async throws {
        // Held by the test: a call that has begun waits here, so it stays in flight until the test has looked.
        let gate = CodemodeLimiter(1)
        #expect(await gate.acquire())
        let counts = Mutex((began: 0, ended: 0))
        let calls = CodemodeCalls(limit: 4) { tool, _ in
            if await gate.acquire() { gate.release() }
            return .success(tool)
        } called: { began, ended in
            counts.withLock { $0 = (began, ended) }
        }
        let works = try (0 ..< 30).map { calls.admit(try request($0)) }
        await withTaskGroup(of: Bool.self) { group in
            for work in works {
                group.addTask { if case .success = await work() { true } else { false } }
            }
            // Twenty-six wait for a place: the other four are in flight, all at once.
            await calls.limiter.waiting(26)
            #expect(counts.withLock { $0.began } == 4 && counts.withLock { $0.ended } == 0)
            gate.release()
            var answered = 0
            for await ran in group where ran { answered += 1 }
            #expect(answered == 30)
        }
        #expect(counts.withLock { $0.began } == 30 && counts.withLock { $0.ended } == 30)
    }

    @Test func `a tool's failure is the error the script reads, and what is not a call is not found`() async throws {
        let calls = CodemodeCalls(limit: 2) { _, _ in
            .failure(CodemodeCallFailure("no such file"))
        } called: { _, _ in
        }
        #expect(await calls.admit(try request(1))() == .failure(JSONRPCError(code: -32000, message: "no such file")))
        let body = try JSONRPC.request(id: .number(2), method: "stop", params: nil)
        guard case .request(let other) = try JSONRPCMessage(parsing: body) else { return }
        #expect(await calls.admit(other)() == .failure(JSONRPCError(code: -32601, message: "Method not found: stop")))
    }
}
