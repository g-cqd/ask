import Foundation
import Testing

@testable import AskAgentCore

/// `gateway` (ADR-0170): read from the person's own file only, an address as host:port, a key of 32 bytes, folders absolute or under
/// `~/`; and the organisation's `policy.gateway*` keys.
@Suite("gateway is read from your own file only, and policy may narrow it")
struct GatewayConfigurationTests {
    private static let key = Data(repeating: 7, count: 32).base64EncodedString()

    private func file(_ json: String, isProject: Bool = false) throws -> ConfigurationFile {
        try ConfigurationFile.parse(Array(json.utf8), path: "c.json", isProject: isProject)
    }

    @Test func `the section is read, and sharing needs it enabled with an address and a key`() throws {
        let section = try #require(
            try file(
                #"{"gateway": {"enabled": true, "address": "192.168.1.20:7443", "key": "\#(Self.key)", "folders": ["~/Developer"]}}"#
            )
            .gateway
        )
        #expect(section.isSharing && section.folders == ["~/Developer"])
        let noKey = try #require(try file(#"{"gateway": {"enabled": true, "address": "h:1"}}"#).gateway)
        #expect(!noKey.isSharing)
    }

    @Test func `a project's file may not set the gateway`() {
        #expect(throws: ConfigurationError.self) { try file(#"{"gateway": {"enabled": true}}"#, isProject: true) }
    }

    @Test func `a bad address, key or folder is refused`() {
        for bad in [
            #"{"gateway": {"address": "no-port"}}"#, #"{"gateway": {"address": "host:0"}}"#,
            #"{"gateway": {"address": ":7443"}}"#, #"{"gateway": {"address": "a b:1"}}"#,
            #"{"gateway": {"key": "c2hvcnQ="}}"#, #"{"gateway": {"folders": ["relative/path"]}}"#
        ] {
            #expect(throws: ConfigurationError.self, "\(bad)") { try file(bad) }
        }
    }

    @Test func `addresses split into host and port, IPv6 in brackets`() {
        #expect(GatewaySection.endpoint("mm.local:7443")?.host == "mm.local")
        #expect(GatewaySection.endpoint("[fe80::1]:7443").map { "\($0.host) \($0.port)" } == "fe80::1 7443")
        #expect(GatewaySection.endpoint("host:65536") == nil)
    }

    @Test func `the policy keys are read`() throws {
        let policy = try #require(
            try file(#"{"policy": {"gatewayAllowed": false, "gatewayApprovals": false, "gatewayStart": true}}"#).policy
        )
        #expect(policy.gatewayAllowed == false && policy.gatewayApprovals == false && policy.gatewayStart == true)
    }
}
