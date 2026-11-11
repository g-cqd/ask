internal import Foundation
internal import Testing

@testable import AskAgentCore

/// "Allow always" for a command opener (ADR-0148): kept until revoked, under a hash of the command as written and what its rule
/// matches, so an edit to either asks again.
@Suite("A command allowed always is remembered until it changes or is revoked")
struct OpenerGrantsTests {
    private let rule = OpenerRule(kind: .file, extensions: ["swift"], command: ["code", "--goto", "{path}:{line}"])

    @Test func `the key holds for the same rule, and changes with its command or its match`() {
        let key = OpenerGrants.key(for: rule)
        #expect(key.count == 64 && key == OpenerGrants.key(for: rule))
        var edited = rule
        edited.command = ["code", "{path}"]
        #expect(OpenerGrants.key(for: edited) != key)
        for change: (inout OpenerRule) -> Void in [
            { $0.extensions = ["swift", "md"] }, { $0.kind = nil }, { $0.pattern = "x" }, { $0.host = "a.com" }
        ] {
            var other = rule
            change(&other)
            #expect(OpenerGrants.key(for: other) != key)
        }
        // Arguments are kept apart: two arguments are not one with a space in it.
        #expect(
            OpenerGrants.key(for: OpenerRule(command: ["a", "b c"]))
                != OpenerGrants.key(for: OpenerRule(command: ["a b", "c"]))
        )
    }

    @Test func `allowed, then asked again once edited or revoked`() {
        var grants = OpenerGrants()
        #expect(!grants.allows(rule))
        grants.allow(rule)
        #expect(grants.allows(rule))
        var edited = rule
        edited.command = ["rm", "{path}"]
        #expect(!grants.allows(edited))
        let listed = grants.listing
        #expect(listed.count == 1 && listed[0].grant.command == ["code", "--goto", "{path}:{line}"])
        #expect(listed[0].grant.match == "files ending .swift")
        #expect(grants.revoke(listed[0].key) && !grants.allows(rule) && !grants.revoke(listed[0].key))
    }

    @Test func `the store is the person's alone, survives a round trip, and a damaged one is an error`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "opener-grants-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "ask/openers.json").path
        #expect(try OpenerGrants.load(path) == OpenerGrants(), "none yet is none allowed")
        var grants = OpenerGrants()
        grants.allow(rule)
        try grants.save(to: path)
        #expect(try OpenerGrants.load(path) == grants)
        let mode = try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue & 0o077 == 0)
        try Data("{not json".utf8).write(to: URL(fileURLWithPath: path))
        #expect(throws: ConfigurationError.self) { try OpenerGrants.load(path) }
        #expect(OpenerGrants.path(environment: ["XDG_STATE_HOME": "/s"], home: "/h") == "/s/ask/openers.json")
        #expect(OpenerGrants.path(environment: [:], home: "/h") == "/h/.local/state/ask/openers.json")
    }

    @Test func `what a rule matches is said in words`() {
        #expect(OpenerRule(command: ["x"]).matchDescription == "every link")
        #expect(
            OpenerRule(kind: .web, host: "github.com", command: ["x"]).matchDescription == "web links at github.com"
        )
        #expect(
            OpenerRule(kind: .file, extensions: ["md", "txt"], pattern: "/work/", command: ["x"]).matchDescription
                == "files ending .md or .txt matching /work/"
        )
        #expect(OpenerRule(kind: .folder, command: ["x"]).matchDescription == "folders")
        #expect(OpenerRule(pattern: "a", command: ["x"]).matchDescription == "links matching a")
    }
}
