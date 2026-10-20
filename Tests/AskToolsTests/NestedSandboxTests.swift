import AemiTesting
import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A program that starts its own macOS sandbox, as SwiftPM does to compile a manifest, cannot do so inside ask's:
/// Seatbelt does not nest. The model must be told that, not that it touched a protected path.
@Suite("A nested sandbox is named as such, with the way out that keeps ask's sandbox", .timeLimit(.minutes(2)))
struct NestedSandboxTests {
    private let world: SandboxWorld

    init() throws { world = try SandboxWorld() }

    private func run(_ command: String) async -> ToolOutput {
        let context = ToolContext(workingDirectory: world.workspace, sandbox: world.policy)
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await BashTool().run(world.input(#"{"command":"\#(quoted)"}"#), in: context)
    }

    @Test func `a command that starts its own sandbox is told the sandboxes cannot nest, and how SwiftPM avoids it`()
        async
    {
        let output = await run("/usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true")
        #expect(output.isError)
        #expect(output.content.contains("sandbox_apply: Operation not permitted"), "the real failure, unedited")
        #expect(output.content.contains("[A program in this command tried to start its own macOS sandbox"))
        #expect(output.content.contains("--disable-sandbox"))
        #expect(output.content.contains("ask's sandbox still applies"))
        #expect(!output.content.contains("which may be why it was refused"), "not the protected-path note")
    }

    @Test func `an unsandboxed run never claims that ask's sandbox applies`() async {
        let context = ToolContext(workingDirectory: world.workspace, sandbox: .unrestricted)
        let output = await BashTool()
            .run(
                world.input(#"{"command":"echo 'sandbox_apply: Operation not permitted'; exit 1"}"#), in: context)
        #expect(output.isError && !output.content.contains("ask's sandbox"))
    }

    @Test func `the system prompt tells the model up front, so it does not have to fail first`() throws {
        let summary = try #require(world.policy.summary)
        #expect(summary.contains("swift build --disable-sandbox"))
        #expect(SandboxPolicy.unrestricted.summary == nil, "nothing to say when nothing is sandboxed")
    }
}
