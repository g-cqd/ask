internal import AemiJSON
internal import AemiTesting
internal import AskAI
internal import Foundation
internal import Testing

@testable import AskMCP

/// A call that is abandoned, because the person aborted or because it took too long. The reference server in the probe ignored
/// `notifications/cancelled` and kept working, so the client cannot count on being obeyed: it tells the server, stops waiting
/// itself, and drops the answer if one still arrives (diary 2026-10-25 (06)).
@Suite("An abandoned call is cancelled with the server and never waited for again", .timeLimit(.minutes(1)))
struct MCPCancellationTests {
    private static let initResult =
        #"{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"s","version":"1"}}"#

    private func started(clock: TestClock = TestClock(), timeout: Duration = .seconds(120)) async throws
        -> (MCPConnection, ScriptedTransport)
    {
        let transport = ScriptedTransport()
        transport.on("initialize") { [$0.result(Self.initResult)] }
        transport.on("tools/call") { _ in [] }  // never answered, unless the test pushes an answer
        let connection = MCPConnection(
            transport: transport, clientName: "ask", clientVersion: "1", clock: clock, requestTimeout: timeout)
        _ = try await connection.start()
        return (connection, transport)
    }

    /// The call's value, cancelling the call if this test is cancelled (by its time limit), so a broken timer fails the test instead of
    /// hanging it.
    private static func value(of call: Task<MCPToolResult, any Error>) async throws -> MCPToolResult {
        try await withTaskCancellationHandler {
            try await call.value
        } onCancel: {
            call.cancel()
        }
    }

    private func cancelled(_ transport: ScriptedTransport) throws -> (requestId: String?, reason: String?) {
        let params = try #require(transport.sent("notifications/cancelled").first?.params)
        let root = try AemiJSON.parse(Array(params.utf8), options: JSONParseOptions(recordsContainerSpans: true)).root
        return (root["requestId"].withRawJSONBytes { String(decoding: $0, as: UTF8.self) }, root["reason"].string)
    }

    @Test func `cancelling the task ends the call at once, and tells the server which request and why`() async throws {
        let (connection, transport) = try await started()
        let call = Task { try await connection.callTool("long", arguments: .empty) }
        await transport.waitUntilSent("tools/call")
        call.cancel()
        await #expect(throws: MCPError.cancelled) { _ = try await call.value }
        let told = try cancelled(transport)
        #expect(told.requestId == transport.sent("tools/call").first?.id)
        #expect(told.reason?.isEmpty == false)
    }

    @Test func `an answer that comes after the cancel is dropped and does not disturb the next call`() async throws {
        let (connection, transport) = try await started()
        let call = Task { try await connection.callTool("long", arguments: .empty) }
        await transport.waitUntilSent("tools/call")
        call.cancel()
        _ = await call.result
        let late = try #require(transport.sent("tools/call").first)
        transport.on("tools/call") { [$0.result(#"{"content":[{"type":"text","text":"second"}]}"#)] }
        transport.push(late.result(#"{"content":[{"type":"text","text":"too late"}]}"#))
        let next = try await connection.callTool("again", arguments: .empty)
        #expect(next.content == [.text("second")])
    }

    @Test func `a task that is cancelled before it even starts sends nothing and fails at once`() async throws {
        let (connection, transport) = try await started()
        let call = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await connection.callTool("never", arguments: .empty)
        }
        await #expect(throws: MCPError.cancelled) { _ = try await call.value }
        #expect(transport.sent("tools/call").count <= 1)
    }

    @Test func `a call that outlasts its time is given up, and the server is told`() async throws {
        let clock = TestClock()
        let (connection, transport) = try await started(clock: clock, timeout: .seconds(30))
        let call = Task { try await connection.callTool("long", arguments: .empty) }
        await transport.waitUntilSent("tools/call")
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(30))
        await #expect(throws: MCPError.timedOut(method: "tools/call")) { _ = try await call.value }
        #expect(try cancelled(transport).requestId == transport.sent("tools/call").first?.id)
    }

    @Test func `a call that is answered in time does not leave its timer running`() async throws {
        let clock = TestClock()
        let (connection, transport) = try await started(clock: clock, timeout: .seconds(30))
        transport.on("tools/call") { [$0.result(#"{"content":[]}"#)] }
        _ = try await connection.callTool("quick", arguments: .empty)
        clock.advance(by: .seconds(300))
        #expect(
            transport.sent("notifications/cancelled").isEmpty,
            "a timer that was not stopped would cancel a finished call")
    }

    @Test func `a call can ask for its own time, longer than the connection's`() async throws {
        let clock = TestClock()
        let (connection, transport) = try await started(clock: clock, timeout: .seconds(30))
        let call = Task { try await connection.callTool("long", arguments: .empty, timeout: .seconds(600)) }
        await transport.waitUntilSent("tools/call")
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(30))
        #expect(transport.sent("notifications/cancelled").isEmpty)
        call.cancel()
        _ = await call.result
    }

    @Test func `a later call with a shorter time is given up at its own time, and the longer one at its own`()
        async throws
    {
        let clock = TestClock()
        let (connection, transport) = try await started(clock: clock, timeout: .seconds(30))
        let long = Task { try await connection.callTool("long", arguments: .empty, timeout: .seconds(600)) }
        await transport.waitUntilSent("tools/call")
        let short = Task { try await connection.callTool("short", arguments: .empty, timeout: .seconds(10)) }
        await transport.waitUntilSent("tools/call", count: 2)
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(10))
        await #expect(throws: MCPError.timedOut(method: "tools/call")) { _ = try await Self.value(of: short) }
        #expect(transport.sent("notifications/cancelled").count == 1, "only the shorter call is given up")
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(590))
        await #expect(throws: MCPError.timedOut(method: "tools/call")) { _ = try await Self.value(of: long) }
    }

    @Test func `many calls at once are each sent once, in turn, and each gets its own answer`() async throws {
        let (connection, transport) = try await started()
        transport.on("tools/call") { [$0.result(#"{"content":[{"type":"text","text":"ok"}]}"#)] }
        let answers = try await withThrowingTaskGroup(of: MCPToolResult.self) { group in
            for _ in 0 ..< 200 { group.addTask { try await connection.callTool("echo", arguments: .empty) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(answers.count == 200 && answers.allSatisfy { $0.content == [.text("ok")] })
        let ids = transport.sent("tools/call").compactMap(\.id)
        #expect(ids.count == 200 && Set(ids).count == 200)
    }
}
