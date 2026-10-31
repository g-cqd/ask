import Testing

@testable import AskAgentCore

/// A network level where commands reach only the model providers' servers (owner, 2026-10-31, roadmap 0021): Seatbelt cannot name a
/// host, so a command under it may reach only localhost, where ask's proxy lets through what goes to a provider. It sits between
/// `localhost` and `any`: narrower than every host, wider than none.
@Suite("The provider network level")
struct ProviderNetworkLevelTests {
    @Test func `it is named provider, in configuration and flags`() {
        #expect(SandboxPolicy.Network(named: "provider") == .provider)
        #expect(SandboxPolicy.Network.provider.description == "provider")
    }

    @Test func `it is wider than localhost and narrower than any`() {
        #expect(SandboxPolicy.Network.localhost < .provider && SandboxPolicy.Network.provider < .any)
        #expect(min(SandboxPolicy.Network.provider, .any) == .provider)
    }

    @Test(arguments: [false, true])
    func `Seatbelt lets a command reach localhost only, where the proxy is`(strictReads: Bool) {
        var policy = SandboxPolicy(network: .provider)
        if strictReads { policy.read = .roots(["/tmp"]) }
        var local = policy
        local.network = .localhost
        let lines = SeatbeltProfile(policy).text.split(separator: "\n").filter { $0.contains("network") }
        #expect(lines == SeatbeltProfile(local).text.split(separator: "\n").filter { $0.contains("network") })
        #expect(lines.contains { $0.contains(#"remote ip "localhost:*""#) })
        #expect(!lines.contains("(allow network*)"))
    }
}
