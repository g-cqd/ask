internal import CryptoKit
internal import Foundation
internal import Testing

@testable import AskGateway

/// The controllers a node trusts: added once, found by key, removed by key or by a fingerprint's start, never by an ambiguous one;
/// keys read as base64 or hex; the file round-trips.
struct GatewayTrustTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey

    @Test func `a key is trusted once, and found by it`() {
        var trust = GatewayTrust()
        let key = Key().publicKey
        let first = trust.trust(key, label: "Safari")
        let again = trust.trust(key, label: "again")
        #expect(first && !again)
        #expect(trust.trusts(key) && !trust.trusts(Key().publicKey))
        #expect(trust.keys.map(\.rawRepresentation) == [key.rawRepresentation])
    }

    @Test func `untrust by whole key or by a fingerprint's start`() {
        var trust = GatewayTrust()
        let (first, second) = (Key().publicKey, Key().publicKey)
        _ = trust.trust(first, label: "a")
        _ = trust.trust(second, label: "b")
        let start = String(GatewayKeys.fingerprint(first).prefix(9))  // "abcd ef01": 8 digits and a space
        let byStart = trust.untrust(start)
        let byKey = trust.untrust(second.rawRepresentation.base64EncodedString())
        #expect(byStart.map(\.label) == ["a"] && byKey.map(\.label) == ["b"])
        #expect(trust.controllers.isEmpty)
    }

    @Test func `a start too short, or matching two, removes nothing`() {
        var trust = GatewayTrust()
        _ = trust.trust(Key().publicKey, label: "a")
        _ = trust.trust(Key().publicKey, label: "b")
        let short = trust.untrust("abc")
        let empty = trust.untrust("")
        #expect(short.isEmpty && empty.isEmpty)
        #expect(trust.controllers.count == 2)
    }

    @Test func `keys read as base64, URL-safe base64 or hex, and fingerprints are 8 groups of 4`() {
        let key = Key().publicKey
        let raw = key.rawRepresentation
        let hex = raw.map { String(format: "%02x", $0) }.joined()
        let urlSafe = raw.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        for text in [raw.base64EncodedString(), urlSafe, hex, " \(hex)\n"] {
            #expect(GatewayKeys.publicKey(text)?.rawRepresentation == raw, "\(text)")
        }
        #expect(GatewayKeys.publicKey("not a key") == nil && GatewayKeys.publicKey(String(hex.dropLast(2))) == nil)
        let groups = GatewayKeys.fingerprint(key).split(separator: " ")
        #expect(groups.count == 8 && groups.allSatisfy { $0.count == 4 })
    }

    @Test func `the file round-trips`() throws {
        var trust = GatewayTrust()
        _ = trust.trust(Key().publicKey, label: "Safari", at: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(GatewayTrust.self, from: JSONEncoder().encode(trust))
        #expect(decoded == trust && decoded.controllers.first?.added == "1970-01-01T00:00:00Z")
    }
}
