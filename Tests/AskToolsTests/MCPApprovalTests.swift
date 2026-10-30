import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// A server's own mark on its tool, put to the user before the first damage (ADR-0111). The mark is the server's word, not a fact;
/// a run with no one to ask allows the call, because naming the server was the user's consent.
@Suite(
    "A tool that may change things is asked about; one the server says is read-only or harmless is not",
    .timeLimit(.minutes(1)))
struct MCPApprovalTests {
    /// Remembers what it was asked and answers what it was told.
    private final class RecordingApprover: Sendable {
        private let state = Mutex<(asked: [DestructiveToolCall], answers: [Bool], nextAnswer: Int)>(([], [], 0))

        /// Answers `answers` in order, then the last one again.
        init(_ answers: [Bool]) { state.withLock { $0.answers = answers } }
        var asked: [DestructiveToolCall] { state.withLock { $0.asked } }

        func answer(_ call: DestructiveToolCall) async -> Bool {
            state.withLock { state in
                state.asked.append(call)
                let index = Swift.min(state.nextAnswer, state.answers.count - 1)
                state.nextAnswer += 1
                return state.answers[index]
            }
        }
    }

    private func context(_ approver: RecordingApprover) -> ToolContext {
        ToolContext(workingDirectory: "/tmp", destructiveApprover: approver.answer)
    }

    private func context() -> ToolContext { ToolContext(workingDirectory: "/tmp") }

    /// A host over one server whose tools are `plain` and `boom`, with `boom` marked destructive.
    private func world() -> (MCPWorld, MCPHost, FakeMCPServer) {
        let world = MCPWorld()
        let fake = FakeMCPServer(
            tools: ["plain", "boom", "look", "add"], destructive: ["boom"], readOnly: ["look"], harmless: ["add"])
        let host = world.host([world.setting("srv")], ["srv": fake])
        return (world, host, fake)
    }

    @Test func `a marked tool is asked, and allowed when the user says yes`() async throws {
        let (world, host, fake) = self.world()
        let approver = RecordingApprover([true])
        host.start()
        await host.waitUntilSettled()
        let output = try await world.call("mcp__srv__boom", #"{"q":"erase everything"}"#, in: context(approver))
        #expect(output == ToolOutput("ran boom"))
        #expect(approver.asked.count == 1 && approver.asked[0].server == "srv" && approver.asked[0].tool == "boom")
        #expect(String(decoding: approver.asked[0].input.bytes, as: UTF8.self) == #"{"q":"erase everything"}"#)
        #expect(fake.calls.map(\.name) == ["boom"], "the call was made after the answer")
        await host.stop()
    }

    @Test func `a refusal is an error the model can act on, and the server is not called`() async throws {
        let (world, host, fake) = self.world()
        let approver = RecordingApprover([false])
        host.start()
        await host.waitUntilSettled()
        let output = try await world.call("mcp__srv__boom", #"{"q":"x"}"#, in: context(approver))
        #expect(output.isError && output.content.contains("did not allow") && output.content.contains("boom"))
        #expect(fake.calls.isEmpty)
        await host.stop()
    }

    @Test func `a tool with no annotations is asked about: by the MCP spec it may destroy (security audit, finding 4)`()
        async throws
    {
        let (world, host, fake) = self.world()
        let approver = RecordingApprover([true])
        host.start()
        await host.waitUntilSettled()
        _ = try await world.call("mcp__srv__plain", "{}", in: context(approver))
        #expect(approver.asked.map(\.tool) == ["plain"] && fake.calls.map(\.name) == ["plain"])
        await host.stop()
    }

    @Test func `a tool the server calls read-only, or not destructive, is not asked about`() async throws {
        let (world, host, fake) = self.world()
        let approver = RecordingApprover([true])
        host.start()
        await host.waitUntilSettled()
        _ = try await world.call("mcp__srv__look", "{}", in: context(approver))
        _ = try await world.call("mcp__srv__add", "{}", in: context(approver))
        #expect(approver.asked.isEmpty && fake.calls.map(\.name) == ["look", "add"])
        await host.stop()
    }

    @Test func `with no one to ask, a marked tool runs: naming the server was the consent`() async throws {
        let (world, host, fake) = self.world()
        host.start()
        await host.waitUntilSettled()
        let output = try await world.call("mcp__srv__boom", "{}", in: context())
        #expect(output == ToolOutput("ran boom") && fake.calls.map(\.name) == ["boom"])
        await host.stop()
    }

    @Test func `the ask is per call: two calls ask twice, the caller remembers grants`() async throws {
        let (world, host, _) = self.world()
        let approver = RecordingApprover([true, true])
        host.start()
        await host.waitUntilSettled()
        _ = try await world.call("mcp__srv__boom", "{}", in: context(approver))
        _ = try await world.call("mcp__srv__boom", "{}", in: context(approver))
        #expect(approver.asked.count == 2, "the adapter asks; the session grant is the approver's to keep")
        await host.stop()
    }

    @Test func `a tool found by search and called through mcp_call is asked about too`() async throws {
        let world = MCPWorld()
        let fake = FakeMCPServer(tools: ["t1", "t2", "t3", "t4", "t5"], destructive: ["t3"], readOnly: ["t2"])
        let host = world.host([world.setting("big")], ["big": fake], maximumDirectTools: 4)
        host.start()
        await host.waitUntilSettled()
        let approver = RecordingApprover([true])
        _ = try await world.call("mcp_search", #"{"query":"t3"}"#, in: context(approver))
        let found = try await world.call("mcp_search", #"{"query":"t3"}"#, in: context(approver))
        #expect(found.content.contains("read-only"), "the search says the tool will be asked about")
        let output = try await world.call(
            "mcp_call", #"{"server":"big","tool":"t3","arguments":{}}"#, in: context(approver))
        #expect(output == ToolOutput("ran t3") && approver.asked.map(\.tool) == ["t3"])
        #expect(
            try await world.call("mcp_call", #"{"server":"big","tool":"t2","arguments":{}}"#, in: context(approver))
                == ToolOutput("ran t2"))
        #expect(approver.asked.count == 1, "the read-only tool was not asked about")
        await host.stop()
    }

    @Test func `a refusal through mcp_call is an error, and the server is not called`() async throws {
        let world = MCPWorld()
        let fake = FakeMCPServer(tools: ["t1", "t2", "t3", "t4", "t5"], destructive: ["t3"])
        let host = world.host([world.setting("big")], ["big": fake], maximumDirectTools: 4)
        host.start()
        await host.waitUntilSettled()
        let approver = RecordingApprover([false])
        let output = try await world.call(
            "mcp_call", #"{"server":"big","tool":"t3","arguments":{}}"#, in: context(approver))
        #expect(output.isError && output.content.contains("did not allow") && fake.calls.isEmpty)
        await host.stop()
    }
}
