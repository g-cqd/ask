import AemiMCP
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A sandboxed MCP server starts inside `sandbox-exec` under the run's policy with the network open (security audit 2026-11-22,
/// MED-10); an unsandboxed one, or any under `--no-sandbox`, starts as itself.
@Suite("A sandboxed MCP server starts inside the run's sandbox")
struct MCPSandboxedLaunchTests {
    private let home = FileManager.default.temporaryDirectory.appending(path: "ask-mcp-sb-\(UUID().uuidString)").path

    private func policy() -> SandboxPolicy {
        var policy = SandboxPolicy.standard(
            home: home,
            configDirectory: home + "/.config/ask",
            stateDirectory: home + "/.local/state/ask",
            workspace: home + "/project"
        )
        policy.network = SandboxPolicy.Network.none
        return policy
    }

    @Test
    func `sandboxed it is sandbox-exec, the profile with the network open, then the command; otherwise the command`() {
        var server = MCPServerSetting(name: "s", command: "npx", args: ["-y", "srv"])
        let plain = MCPHub.launch("npx", server, environment: [:], inheriting: [:], sandbox: policy())
        #expect(plain.executable == "npx" && plain.arguments == ["-y", "srv"])
        server.sandbox = true
        let inside = MCPHub.launch("npx", server, environment: [:], inheriting: [:], sandbox: policy())
        #expect(inside.executable == "/usr/bin/sandbox-exec")
        #expect(Array(inside.arguments.suffix(3)) == ["npx", "-y", "srv"])
        var open = policy()
        open.network = .any
        #expect(
            Array(inside.arguments.dropLast(3)) == SeatbeltProfile(open).arguments,
            "the run's policy, its network open"
        )
        let unrestricted = MCPHub.launch("npx", server, environment: [:], inheriting: [:], sandbox: .unrestricted)
        #expect(unrestricted.executable == "npx", "under --no-sandbox nothing is sandboxed")
    }
}
