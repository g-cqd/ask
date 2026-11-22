import Darwin
import Foundation
import Testing

@testable import AskAgentCore

/// `policy` (ADR-0168): what only an organisation decides. Its allowlists match with `*`; what it refuses is said; and no file but the
/// organisation's requirements may set it.
@Suite("An organisation's policy", .serialized)
struct PolicySectionTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-policy-\(UUID().uuidString)").path

    private func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: URL(filePath: path))
    }

    private func loader() -> ConfigurationLoader {
        ConfigurationLoader(
            project: root + "/project",
            configDirectory: root + "/config",
            environment: [:],
            managed: ManagedFiles(directory: root + "/managed", owner: getuid())
        )
    }

    @Test func `an allowlist matches names, with star matching any run of characters`() {
        #expect(PolicySection.allows(nil, "anything"))
        #expect(PolicySection.allows(["claude-*"], "claude-opus-5-5"))
        #expect(PolicySection.allows(["*-mini"], "gpt-5-mini") && !PolicySection.allows(["*-mini"], "gpt-5-mini-high"))
        #expect(PolicySection.allows(["work"], "work") && !PolicySection.allows(["work"], "workshop"))
        #expect(PolicySection.allows(["a*b*c"], "a-b-c") && !PolicySection.allows(["a*b*c"], "a-c"))
        #expect(!PolicySection.allows([], "anything"), "an empty list allows nothing")
    }

    @Test func `what the policy refuses is said, and an unset policy allows everything`() {
        let open = PolicySection()
        #expect(open.refusal(noSandbox: true, yes: true, provider: "any", model: "any") == nil)
        var policy = PolicySection()
        policy.allowNoSandbox = false
        policy.allowYes = false
        policy.providers = ["work"]
        policy.models = ["claude-*"]
        #expect(
            policy.refusal(noSandbox: true, yes: false, provider: "work", model: "claude-x")?.contains("--no-sandbox")
                == true
        )
        #expect(
            policy.refusal(noSandbox: false, yes: true, provider: "work", model: "claude-x")?.contains("--yes") == true
        )
        #expect(
            policy.refusal(noSandbox: false, yes: false, provider: "home", model: "claude-x")
                == "the connection home; it allows work"
        )
        #expect(
            policy.refusal(noSandbox: false, yes: false, provider: "work", model: "gpt-5")
                == "the model gpt-5; it allows claude-*"
        )
        #expect(policy.refusal(noSandbox: false, yes: false, provider: "work", model: "claude-x") == nil)
    }

    @Test func `only the organisation's requirements may set it`() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/config/config.json", #"{"policy": {"allowYes": true}}"#)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try FileManager.default.removeItem(atPath: root + "/config/config.json")
        try write(root + "/managed/defaults.json", #"{"policy": {"allowYes": false}}"#)
        #expect(throws: ConfigurationError.self) { try loader().load() }
        try FileManager.default.removeItem(atPath: root + "/managed/defaults.json")
        try write(root + "/managed/requirements.json", #"{"policy": {"allowYes": false, "models": ["claude-*"]}}"#)
        try write(root + "/managed/requirements.d/10-team.json", #"{"policy": {"models": ["claude-opus-*"]}}"#)
        let policy = try loader().load().configuration.policy
        #expect(policy.value.allowYes == false && policy.value.models == ["claude-opus-*"], "a later drop-in replaces")
        #expect(policy.source == .managed(root + "/managed/requirements.d/10-team.json", required: true))
    }
}
