import AskAgentCore
import Testing

@testable import AskSession

/// A client names a server for a person to read; ask names it in every tool's name (ADR-0154).
@Suite("The MCP servers a client gives a session become settings ask can run")
struct ClientServersTests {
    @Test(arguments: [
        ["filesystem", "filesystem"], ["My Server (2)", "My-Server--2-"], ["a__b___c", "a_b_c"], ["--lead", "lead"],
        ["", "server"], ["···", "server"], ["été", "t-"],
        ["a-name-that-is-much-longer-than-thirty-two-characters", "a-name-that-is-much-longer-than-"]
    ])
    func `a name is made one a tool's name can hold`(pair: [String]) {
        let made = ClientServers.allowed(pair[0])
        #expect(made == pair[1])
        #expect(MCPServerSetting.isValid(name: made))
    }

    @Test func `no two servers share a name, and one that was cut to fit still fits`() {
        let long = String(repeating: "n", count: 40)
        let names =
            ClientServers.settings(
                ["git", "git", "git", long, long].map { MCPServerSetting(name: $0, command: "/bin/true") },
                in: "/work"
            )
            .map(\.name)
        // Typed and named before the expectation: inside it, the literal took CI's compiler past its limit for one expression.
        let cut = String(long.prefix(32))
        let second = String(long.prefix(30)) + "-2"
        let expected: [String] = ["git", "git-2", "git-3", cut, second]
        #expect(names == expected)
        #expect(names.allSatisfy(MCPServerSetting.isValid(name:)))
    }

    /// `ask serve` runs wherever the client started it, which is no session's folder. Client-supplied servers are
    /// treated as untrusted (sandboxed by default, N-A4).
    @Test func `a program runs in the session's folder unless it says where, and an address has no folder`() {
        let made = ClientServers.settings(
            [
                MCPServerSetting(name: "a", command: "/bin/true", args: ["x"], env: ["K": "v"]),
                MCPServerSetting(name: "b", command: "/bin/true", cwd: "/elsewhere"),
                MCPServerSetting(name: "c", url: "https://example.test/mcp", headers: ["H": "v"])
            ],
            in: "/work"
        )
        #expect(made.map(\.cwd) == ["/work", "/elsewhere", nil])
        #expect(made[0].args == ["x"] && made[0].env == ["K": "v"] && made[2].headers == ["H": "v"])
        #expect(made.allSatisfy { $0.isSandboxed })
    }
}
