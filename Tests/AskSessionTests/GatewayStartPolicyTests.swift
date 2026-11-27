internal import Foundation
internal import Testing

@testable import AskSession

/// `GatewayStartPolicy` (ADR-0170): `policy.gatewayStart` and `gateway.folders` bound where a controller can start a session, with
/// `~/` and symlinks resolved so neither `..` nor a symlink inside an allowed folder can escape it.
@Suite("GatewayStartPolicy resolves symlinks and confines start folders to gateway.folders")
struct GatewayStartPolicyTests {
    @Test func `allowed subdirectories pass, while policy off, outside paths, files and symlink escapes are refused`()
        throws
    {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ask-gw-folders-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("work", isDirectory: true)
        let subproject = workspace.appendingPathComponent("app", isDirectory: true)
        let secret = root.appendingPathComponent("secret", isDirectory: true)
        try FileManager.default.createDirectory(at: subproject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = workspace.appendingPathComponent("README.md")
        try Data("hi".utf8).write(to: file)
        let escape = workspace.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: secret)

        let allowed = ["~/work"]
        let home = root.path

        let resolved = try GatewayStartPolicy.resolve("~/work/app", allowed: allowed, policyAllows: true, home: home)
        #expect(resolved.hasSuffix("/work/app"))

        #expect(throws: GatewayStartPolicy.Refusal.self) {
            _ = try GatewayStartPolicy.resolve("~/work/app", allowed: allowed, policyAllows: false, home: home)
        }
        #expect(throws: GatewayStartPolicy.Refusal.self) {
            _ = try GatewayStartPolicy.resolve("~/work/app", allowed: nil, policyAllows: true, home: home)
        }
        #expect(throws: GatewayStartPolicy.Refusal.self) {
            _ = try GatewayStartPolicy.resolve(
                workspace.path + "/../secret",
                allowed: allowed,
                policyAllows: true,
                home: home
            )
        }
        #expect(throws: GatewayStartPolicy.Refusal.self) {
            _ = try GatewayStartPolicy.resolve(escape.path, allowed: allowed, policyAllows: true, home: home)
        }
        #expect(throws: GatewayStartPolicy.Refusal.self) {
            _ = try GatewayStartPolicy.resolve(file.path, allowed: allowed, policyAllows: true, home: home)
        }
    }
}
