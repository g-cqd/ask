internal import Testing

@testable import AskAI

/// Which `Host` a callback may name: this machine, on the port the listener bound. Anything else is a page on the
/// internet talking to a local server through the user's browser (DNS rebinding).
@Suite("Only a host that is this machine on the bound port may reach the callback")
struct LoopbackHostTests {
    @Test(arguments: ["localhost:1455", "127.0.0.1:1455", "[::1]:1455", "LOCALHOST:1455"])
    func `this machine on the bound port is allowed`(host: String) {
        #expect(LoopbackRequest.allows(host: host, port: 1455))
    }

    @Test(arguments: [
        "evil.example:1455", "localhost:1456", "localhost", "127.0.0.1", "localhost.evil.example:1455",
        "127.0.0.1:1455.evil.example", "localhost:1455@evil.example", ""
    ])
    func `anything else is refused`(host: String) {
        #expect(!LoopbackRequest.allows(host: host, port: 1455))
    }

    @Test func `no host at all is refused`() { #expect(!LoopbackRequest.allows(host: nil, port: 1455)) }
}
