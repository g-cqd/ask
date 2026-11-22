import Testing

@testable import AskAI

/// Addresses that reach inward, read as bytes in any spelling (security audit 2026-11-22, CRIT-05): the string prefixes before this
/// missed `fe81::` to `febf::`, the expanded mapped forms, NAT64, multicast and the reserved IPv4 ranges.
@Suite("An address that reaches inward, in any spelling")
struct InwardAddressTests {
    @Test func `loopback, private, link-local, shared, reserved, multicast and documentation ranges are inward`() {
        for literal in [
            "127.0.0.1", "127.255.0.9", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254",
            "100.64.0.1",
            "0.0.0.0", "224.0.0.1", "239.255.255.250", "240.0.0.1", "255.255.255.255", "198.18.0.1", "192.0.2.1",
            "203.0.113.9",
            "::", "::1", "[::1]", "fe80::1", "fe81::1", "febf::1", "fec0::1", "fc00::1", "fd12:3456::1", "ff02::1",
            "::ffff:127.0.0.1", "::ffff:7f00:1", "0:0:0:0:0:ffff:7f00:1", "0000:0000:0000:0000:0000:ffff:a9fe:a9fe",
            "64:ff9b::a9fe:a9fe", "::127.0.0.1", "2001:db8::1", "fe80::1%en0", "[0:0:0:0:0:ffff:169.254.169.254]"
        ] {
            #expect(InwardAddress.contains(literal), "\(literal)")
        }
    }

    @Test func `the public internet, and names, are not`() {
        for literal in [
            "8.8.8.8", "1.1.1.1", "172.32.0.1", "100.128.0.1", "192.169.0.1", "2606:4700::1111", "::ffff:8.8.8.8",
            "64:ff9b::808:808", "fec0", "example.com", "localhost", "127.1", ""
        ] {
            #expect(!InwardAddress.contains(literal), "\(literal)")
        }
    }
}
