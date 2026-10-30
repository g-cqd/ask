import AskAI
import Foundation
import Testing

@testable import AskAgentCore

/// The paths a model could use to act outside ask later, and other tools' credentials, are protected, but only behind a question
/// (security audit 2026-10-29, findings 1 to 3): a call's request for one is put to the person, and an allowed request lifts that
/// protection for the call. ask's own directories stay out of reach whatever is answered.
@Suite("Protected behind a question: places that run later, and other tools' credentials")
struct SandboxAskablePathsTests {
    private let home = "/Users/someone"
    private let workspace: String

    init() throws {
        let made = FileManager.default.temporaryDirectory.appending(path: "ask-askable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made.appending(path: ".git"), withIntermediateDirectories: true)
        workspace = String(cString: realpath(made.path, nil))
    }

    private func standard(allowRead: [String] = [], allowWrite: [String] = []) -> SandboxPolicy {
        SandboxPolicy.standard(
            home: home, configDirectory: home + "/.config/ask", stateDirectory: home + "/.local/state/ask",
            allowRead: allowRead, workspace: workspace, allowWrite: allowWrite)
    }

    private func may(_ policy: SandboxPolicy, _ capability: SandboxCapability, _ path: String) -> Bool {
        policy.authorize(capability, path: path, relativeTo: workspace).isAllowed
    }

    @Test func `what runs outside ask later cannot be written`() {
        let policy = standard()
        for path in [
            "~/.zshrc", "~/.zprofile", "~/.bash_profile", "~/.bashrc", "~/.profile", "~/.config/fish/config.fish",
            "~/Library/LaunchAgents/com.x.plist", "~/.ssh/authorized_keys", "~/.ssh/config", "~/.gitconfig",
            "~/.config/git/config", ".git/hooks/pre-commit", ".git/config", "/Library/LaunchAgents/x.plist"
        ] {
            let full = path.hasPrefix("~/") ? home + path.dropFirst(1) : path
            #expect(!may(policy, .write, full), "\(path)")
        }
        for path in ["main.swift", ".git/HEAD", ".git/objects/ab/cd", home + "/notes.txt"] {
            #expect(may(policy, .write, path), "\(path)")
        }
        #expect(may(policy, .read, home + "/.ssh/config") && may(policy, .read, ".git/config"), "reading them is fine")
    }

    @Test func `a workspace that is not a repository yet has no hooks to protect, so a repository can be made`() throws
    {
        let fresh = FileManager.default.temporaryDirectory.appending(path: "ask-fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        let path = String(cString: realpath(fresh.path, nil))
        let policy = SandboxPolicy.standard(
            home: home, configDirectory: home + "/.config/ask", stateDirectory: home + "/.local/state/ask",
            workspace: path)
        #expect(policy.authorize(.write, path: ".git/hooks/pre-commit", relativeTo: path).isAllowed)
    }

    @Test func `other tools' credentials cannot be read`() {
        let policy = standard()
        for path in [
            ".config/gh/hosts.yml", ".docker/config.json", ".kube/config", ".npmrc", ".pypirc",
            ".config/gcloud/credentials.db",
            ".azure/accessTokens.json", ".git-credentials",
            "Library/Application Support/Google/Chrome/Default/Cookies", "Library/Cookies/Cookies.binarycookies",
            ".aws/credentials"
        ] {
            #expect(!may(policy, .read, home + "/" + path), "\(path)")
        }
    }

    @Test func `more secret stores can be added, and are askable like the rest`() throws {
        let policy = SandboxPolicy.standard(
            home: home, configDirectory: home + "/.config/ask", stateDirectory: home + "/.local/state/ask",
            otherSecrets: ([".agent"], [".other/token.json"]))
        #expect(!may(policy, .read, home + "/.agent/auth.json") && !may(policy, .read, home + "/.other/token.json"))
        let request = try #require(try SandboxRequest.in(input(#"{"sandbox":{"read":["/Users/someone/.agent"]}}"#)))
        #expect(may(request.granted(over: policy, workingDirectory: workspace), .read, home + "/.agent/auth.json"))
    }

    @Test func `a request for one of them is put to the person, and allowed, lifts it for the call`() throws {
        let policy = standard()
        let request = try #require(try SandboxRequest.in(input(#"{"sandbox":{"write":["/Users/someone/.zshrc"]}}"#)))
        guard case .refused(let asked) = request.applied(to: policy, workingDirectory: workspace) else {
            return #expect(Bool(false), "a protected path is not taken without asking")
        }
        #expect(asked.first?.contains(".zshrc") == true)
        let granted = request.granted(over: policy, workingDirectory: workspace)
        #expect(may(granted, .write, home + "/.zshrc"))
        #expect(!may(granted, .write, home + "/.bashrc"), "only what was asked for")
        let read = try #require(try SandboxRequest.in(input(#"{"sandbox":{"read":["/Users/someone/.config/gh"]}}"#)))
        #expect(may(read.granted(over: policy, workingDirectory: workspace), .read, home + "/.config/gh/hosts.yml"))
    }

    @Test func `ask's own directories are never lifted, whatever is granted`() throws {
        let policy = standard()
        let request = try #require(
            try SandboxRequest.in(input(#"{"sandbox":{"read":["/Users/someone/.config/ask"]}}"#)))
        #expect(
            !may(
                request.granted(over: policy, workingDirectory: workspace), .read,
                home + "/.config/ask/credentials.json"))
    }

    @Test func `the person's allowRead and allowWrite lift them from the configuration`() {
        let policy = standard(
            allowRead: [home + "/.config/gh"], allowWrite: [workspace + "/.git/config", home + "/.zshrc"])
        #expect(may(policy, .read, home + "/.config/gh/hosts.yml") && !may(policy, .read, home + "/.kube/config"))
        #expect(may(policy, .write, ".git/config") && may(policy, .write, home + "/.zshrc"))
        #expect(!may(policy, .write, ".git/hooks/pre-commit"))
    }

    private func input(_ json: String) -> AskAI.JSONObject { try! AskAI.JSONObject(validating: Array(json.utf8)) }
}
