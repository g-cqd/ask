internal import Darwin
internal import Testing

@testable import AskTools

@Suite("Port readiness looks at this machine only (ADR-0121)")
struct PortWaitLoopbackTests {
    @Test func `the address probed is 127.0.0.1`() {
        let address = PortWait.loopback(8080)
        #expect(in_addr_t(bigEndian: address.sin_addr.s_addr) == 0x7F00_0001)
        #expect(in_port_t(bigEndian: address.sin_port) == 8080)
    }
}
