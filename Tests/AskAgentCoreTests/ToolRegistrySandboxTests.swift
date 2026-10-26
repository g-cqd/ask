import AskAI
import Foundation
import Synchronization
import Testing

@testable import AskAgentCore

/// The registry applies a call's `sandbox` argument: the tool runs with the narrowed policy, or not at all.
@Suite("The registry runs a tool under the call's narrowed sandbox, or refuses the call")
struct ToolRegistrySandboxTests {
    /// Records the policy each call ran under.
    private final class Spy: Tool {
        let definition = ToolDefinition(name: "spy", description: "Record.") { ToolProperty.string("x").optional }
        let seen = Mutex<[SandboxPolicy]>([])
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            seen.withLock { $0.append(context.sandbox) }
            return ToolOutput("ran")
        }
    }

    private func call(_ spy: Spy, _ json: String, policy: SandboxPolicy) async throws -> ToolOutput {
        let registry = try ToolRegistry([spy])
        return await registry.run(
            name: "spy", input: try JSONObject(validating: Array(json.utf8)),
            in: ToolContext(workingDirectory: "/tmp", sandbox: policy))
    }

    @Test func `a narrowing call runs with the narrowed policy`() async throws {
        let spy = Spy()
        let output = try await call(
            spy, #"{"x":"a","sandbox":{"network":"none"}}"#, policy: SandboxPolicy(network: .localhost))
        #expect(output == ToolOutput("ran"))
        #expect(spy.seen.withLock { $0 } == [SandboxPolicy(network: SandboxPolicy.Network.none)])
    }

    @Test func `a call without the argument runs under the run's policy`() async throws {
        let spy = Spy()
        _ = try await call(spy, #"{"x":"a"}"#, policy: SandboxPolicy(network: .localhost))
        #expect(spy.seen.withLock { $0 } == [SandboxPolicy(network: .localhost)])
    }

    @Test func `a widening call does not run, and is refused without telling the model the run's policy`() async throws
    {
        let spy = Spy()
        let output = try await call(spy, #"{"sandbox":{"network":"any"}}"#, policy: SandboxPolicy(network: .localhost))
        #expect(output.isError)
        #expect(output.content == "Not permitted: that request is refused.")
        #expect(!output.content.contains("localhost"), "the run's own policy is not told to the model")
        #expect(spy.seen.withLock { $0 }.isEmpty)
    }

    @Test func `a malformed request does not run either`() async throws {
        let spy = Spy()
        let output = try await call(spy, #"{"sandbox":{"network":"lan"}}"#, policy: SandboxPolicy())
        #expect(output.isError && output.content.hasPrefix("Invalid sandbox for spy:"))
        #expect(spy.seen.withLock { $0 }.isEmpty)
    }
}
