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
                at: made.appending(path: directory),
                withIntermediateDirectories: true
            )
        }
        home = String(cString: realpath(made.path, nil))
    }

    private func standard(allowRead: [String] = [], denyRead: [String] = []) -> SandboxPolicy {
        SandboxPolicy.standard(
            home: home,
            configDirectory: home + "/.config/ask",
            stateDirectory: home + "/.local/state/ask",
            allowRead: allowRead,
            denyRead: denyRead
        )
    }

    private func allowed(_ policy: SandboxPolicy, _ capability: SandboxCapability, _ relative: String) -> Bool {
        policy.authorize(capability, path: home + "/" + relative, relativeTo: home).isAllowed
    }

    @Test
    func
        `ask's configuration cannot be read or written; of its state only the commands' output can be read, none written`()
    {
        let policy = standard()
        #expect(!allowed(policy, .read, ".config/ask/credentials.json") && !allowed(policy, .write, ".config/ask/x"))
        // Security audit 2026-11-22, HIGH-08: every project's sessions, the session keys and ask's log are not the model's to read.
        for path in [
            ".local/state/ask/sessions/p/s.jsonl", ".local/state/ask/sessions/other/s.jsonl",
            ".local/state/ask/keys.json",
            ".local/state/ask/session-encryption.json", ".local/state/ask/stderr.log"
        ] {
            #expect(!allowed(policy, .read, path), "\(path)")
        }
        #expect(allowed(policy, .read, ".local/state/ask/output/p/1-2-3.log"))
        #expect(
            !allowed(policy, .write, ".local/state/ask/output/p/1-2-3.log")
                && !allowed(policy, .write, ".local/state/ask/sessions/s.jsonl")
        )
    }

    /// Security audit 2026-11-22, CRIT-01 and MED-08: Sunset's vault and cookies in every variant, Safari's, password managers' and
    /// developer credentials; other apps' URL storage, which builds use, stays readable.
    @Test func `browsers' data, password managers and credentials files are unreadable, other apps' storage is not`() {
        let policy = standard()
        for path in [
            "Library/Application Support/Sunset/Vaults/personal.vault",
            "Library/Application Support/Sunset Dev/state.sqlite",
            "Library/HTTPStorages/studio.aemi.sunset.binarycookies",
            "Library/HTTPStorages/studio.aemi.sunset.dev.binarycookies",
            "Library/WebKit/studio.aemi.sunset.lab/WebsiteData/x", "Library/Caches/studio.aemi.sunset/x",
            "Library/Safari/History.db",
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
            "Library/HTTPStorages/com.apple.Safari/x", "Library/Group Containers/2BUA8C4S2C.com.1password/x",
            ".password-store/a.gpg",
            ".pgpass", ".cargo/credentials.toml", ".zsh_history", "Library/Messages/chat.db"
        ] {
            #expect(!allowed(policy, .read, path), "\(path)")
            #expect(!allowed(policy, .write, path), "and unwritable: \(path)")
        }
        for path in [
            "Library/HTTPStorages/swift-build/x", "Library/WebKit/com.apple.dt.Xcode/x", ".cargo/config.toml",
            ".m2/settings.xml"
        ] {
            #expect(allowed(policy, .read, path), "\(path)")
        }
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
}
