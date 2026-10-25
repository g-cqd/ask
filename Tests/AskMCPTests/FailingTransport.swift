@testable import AskMCP

/// A transport whose writes always fail, as a pipe to a process that has died does.
struct FailingTransport: MCPTransport {
    struct Broken: Error {}

    let incoming = AsyncStream<[UInt8]> { _ in }

    func send(_ message: [UInt8]) async throws { throw Broken() }

    func close() async {}
}
