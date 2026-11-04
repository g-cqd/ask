import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// A remote server that refuses for want of a sign-in is not a failure like the others (roadmap 0067): it says it needs one, the hub
/// passes that on so the person can be asked, and once signed in it connects without the rest being restarted.
@Suite("A server that needs a sign-in says so, and connects once signed in", .timeLimit(.minutes(1)))
struct MCPHubSignInTests {
    @Test func `a refusal for want of a sign-in is its own state, passed on by name, and a reconnect connects it`()
        async throws
    {
        let other = FakeMCPServer(tools: ["a"])
        let made = Mutex(0)
        let signedIn = Mutex(false)
        let hub = MCPHub(environment: [:]) { server, _, _ in
            guard server.name == "docs" else { return other }
            made.withLock { $0 += 1 }
            let fake = FakeMCPServer(tools: ["search"])
            if !signedIn.withLock({ $0 }) { fake.requireSignIn(MCPAuthChallenge(scope: "files")) }
            return fake
        }
        hub.apply([
            MCPServerSetting(name: "docs", url: "https://docs.example/mcp"),
            MCPServerSetting(name: "other", command: "x")
        ])
        await hub.waitUntilSettled()
        #expect(hub.status.first { $0.name == "docs" }?.state == .needsSignIn)
        #expect(hub.status.first { $0.name == "other" }?.state == .ready(offered: 1, of: 1))
        var asked: String?
        for await name in hub.signInNeeds {
            asked = name
            break
        }
        #expect(asked == "docs")
        #expect(hub.signInChallenge(for: "docs")?.scope == "files")
        #expect(MCPReport.lines(hub.status).contains { $0.contains("docs") && $0.contains("/mcp login docs") })
        signedIn.withLock { $0 = true }
        await hub.reconnect("docs")
        #expect(hub.status.first { $0.name == "docs" }?.state == .ready(offered: 1, of: 1))
        #expect(made.withLock { $0 } == 2 && !other.isClosed, "only that server is started again")
    }
}
