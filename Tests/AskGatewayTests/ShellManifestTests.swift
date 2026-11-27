internal import CryptoKit
internal import Foundation
internal import Testing

@testable import AskGateway

/// `ShellManifest` and `GatewayLaunchdPlist` (ADR-0170): signing and verifying a static shell bundle, catching any tampered or missing
/// file or wrong pinned key, and rendering launchd user-agent plists safely.
@Suite("ShellManifest pins the release key and detects tampered or missing shell files")
struct ShellManifestTests {
    @Test func `a signed shell verifies, while a tampered file, missing file or wrong key is refused`() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ask-shell-sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("<!doctype html><title>ask</title>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("console.log('ok');".utf8).write(to: root.appendingPathComponent("app.js"))
        try Data("// service worker".utf8).write(to: root.appendingPathComponent("sw.js"))

        let key = Curve25519.Signing.PrivateKey()
        let signed = try ShellManifest.signDirectory(root.path, with: key)
        #expect(signed.files.keys.sorted() == ["/app.js", "/index.html"])

        let verified = try ShellManifest.verifyDirectory(root.path, pinnedKey: key.publicKey)
        #expect(verified == signed)

        let otherKey = Curve25519.Signing.PrivateKey().publicKey
        #expect(throws: ShellManifest.Failure.invalidSignature) {
            _ = try ShellManifest.verifyDirectory(root.path, pinnedKey: otherKey)
        }

        try Data("console.log('tampered');".utf8).write(to: root.appendingPathComponent("app.js"))
        #expect(throws: ShellManifest.Failure.tamperedFile("/app.js")) {
            _ = try ShellManifest.verifyDirectory(root.path, pinnedKey: key.publicKey)
        }

        try FileManager.default.removeItem(at: root.appendingPathComponent("app.js"))
        #expect(throws: ShellManifest.Failure.missingFile("/app.js")) {
            _ = try ShellManifest.verifyDirectory(root.path, pinnedKey: key.publicKey)
        }
    }

    @Test func `launchd plists escape XML characters in arguments and paths`() {
        let plist = GatewayLaunchdPlist.render(
            label: "studio.aemi.ask.gateway.node",
            arguments: ["/usr/local/bin/ask", "gateway", "node", "--label", "a&b<c>"],
            logDirectory: "/tmp/logs"
        )
        #expect(plist.contains("<string>studio.aemi.ask.gateway.node</string>"))
        #expect(plist.contains("<string>a&amp;b&lt;c&gt;</string>"))
    }
}
