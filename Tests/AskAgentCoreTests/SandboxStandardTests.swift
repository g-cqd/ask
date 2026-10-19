import Foundation
import Testing

@testable import AskAgentCore

/// The default policy's contents: what it protects, and what the user's lists can and cannot change.
@Suite("The default policy protects ask and the secret stores, and the user's lists adjust only the secrets")
struct SandboxStandardTests {
    private let home: String

    init() throws {
        let made = FileManager.default.temporaryDirectory.appending(path: "ask-std-\(UUID().uuidString)")
        for directory in [
            ".config/ask", ".local/state/ask", ".aws", ".gnupg", ".ssh", "Library/Keychains", "work", "clients"
        ] {
            try FileManager.default.createDirectory(
                at: made.appending(path: directory), withIntermediateDirectories: true)
        }
        home = String(cString: realpath(made.path, nil))
    }

    private func standard(allowRead: [String] = [], denyRead: [String] = []) -> SandboxPolicy {
        SandboxPolicy.standard(
            home: home, configDirectory: home + "/.config/ask", stateDirectory: home + "/.local/state/ask",
            allowRead: allowRead, denyRead: denyRead)
    }

    private func allowed(_ policy: SandboxPolicy, _ capability: SandboxCapability, _ relative: String) -> Bool {
        policy.authorize(capability, path: home + "/" + relative, relativeTo: home).isAllowed
    }

    @Test func `ask's configuration cannot be read or written, its state can be read but not written`() {
        let policy = standard()
        #expect(!allowed(policy, .read, ".config/ask/credentials.json") && !allowed(policy, .write, ".config/ask/x"))
        #expect(allowed(policy, .read, ".local/state/ask/sessions/s.jsonl"))
        #expect(!allowed(policy, .write, ".local/state/ask/sessions/s.jsonl"))
    }

    @Test func `the secret stores are unreadable, and ssh's private keys are but its config is not`() {
        let policy = standard()
        for path in [
            ".aws/credentials", ".gnupg/private-keys-v1.d/k", "Library/Keychains/login.keychain-db", ".netrc",
            ".ssh/id_rsa", ".ssh/id_ed25519", ".ssh/id_ecdsa_sk"
        ] {
            #expect(!allowed(policy, .read, path), "\(path)")
        }
        for path in [".ssh/config", ".ssh/known_hosts", ".ssh/id_ed25519.pub", "work/anything"] {
            #expect(allowed(policy, .read, path), "\(path)")
        }
    }

    @Test func `allowing a secret store lifts exactly that one`() {
        let policy = standard(allowRead: [home + "/.aws"])
        #expect(allowed(policy, .read, ".aws/credentials") && !allowed(policy, .read, ".gnupg/x"))
        #expect(!allowed(policy, .read, ".ssh/id_rsa"))
    }

    @Test func `allowing cannot lift ask's own directories, however it is spelled`() {
        for spelling in [home + "/.config/ask", home + "/.CONFIG/ASK", home + "/.config", home + "/.local/state/ask"] {
            let policy = standard(allowRead: [spelling])
            #expect(!allowed(policy, .read, ".config/ask/credentials.json"), "\(spelling)")
            #expect(!allowed(policy, .write, ".config/ask/config.json"), "\(spelling)")
            #expect(!allowed(policy, .write, ".local/state/ask/sessions/s.jsonl"), "\(spelling)")
        }
    }

    @Test func `an allowance spelled through a link or in another case lifts the same store`() throws {
        try FileManager.default.createSymbolicLink(atPath: home + "/awslink", withDestinationPath: home + "/.aws")
        #expect(allowed(standard(allowRead: [home + "/awslink"]), .read, ".aws/credentials"))
        #expect(allowed(standard(allowRead: [home + "/.AWS"]), .read, ".aws/credentials"))
    }

    @Test func `extra directories can be kept unreadable, which only narrows`() {
        let policy = standard(denyRead: [home + "/clients"])
        #expect(!allowed(policy, .read, "clients/acme/notes.txt") && !allowed(policy, .write, "clients/x"))
        #expect(allowed(policy, .read, "work/file"))
    }

    @Test func `the protected set is what the summary tells the model, and an empty policy has none`() throws {
        let summary = try #require(standard().summary)
        #expect(summary.hasPrefix("Sandbox: These paths cannot be read, written or moved: "))
        #expect(summary.contains(home + "/.config/ask") && summary.contains(home + "/.aws"))
        #expect(summary.contains("These can be read but not written or moved: " + home + "/.local/state/ask."))
        #expect(summary.hasSuffix("say so if a task needs it."))
        #expect(SandboxPolicy.unrestricted.summary == nil)
        #expect(SandboxPolicy(network: .none).summary?.contains("There is no network access.") == true)
        #expect(
            SandboxPolicy(write: .roots(["/w"])).summary?
                .contains("Writes are allowed only under /w and temporary directories.") == true)
    }
}
