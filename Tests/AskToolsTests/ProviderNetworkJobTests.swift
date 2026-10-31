import AemiTesting
import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A command under the `provider` network level (roadmap 0021) is pointed at ask's proxy, which ask starts on first use: it reaches the
/// allowed providers through it, and a host outside them is refused by the proxy, never reached.
@Suite("Commands under the provider level go through the proxy", .serialized, .timeLimit(.minutes(1)))
struct ProviderNetworkJobTests {
    private let world: SandboxWorld

    init() throws { world = try SandboxWorld() }

    private func run(_ command: String) async -> ToolOutput {
        var policy = world.policy
        policy.network = .provider
        let context = ToolContext(workingDirectory: world.workspace, sandbox: policy)
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await BashTool().run(world.input(#"{"command":"\#(quoted)","shell":"/bin/bash"}"#), in: context)
    }

    @Test func `the command is given the proxy's address`() async {
        ProviderAccess.allow([.init(host: "api.anthropic.com", port: 443)])
        let output = await run("printf '%s|%s' \"$HTTPS_PROXY\" \"$https_proxy\"")
        #expect(output.content.hasPrefix("http://127.0.0.1:"), "\(output.content)")
        let halves = output.content.split(separator: "\n")[0].split(separator: "|")
        #expect(halves.count == 2 && halves[0] == halves[1], "\(output.content)")
    }

    @Test func `a host outside the providers is refused by the proxy`() async {
        ProviderAccess.allow([.init(host: "api.anthropic.com", port: 443)])
        let output = await run("curl -sS -o /dev/null https://example.com 2>&1; true")
        #expect(output.content.contains("403"), "\(output.content)")
    }
}
