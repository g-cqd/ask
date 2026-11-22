internal import AskAgentCore
internal import Darwin
internal import Foundation
internal import Testing

@testable import AskSession

/// A run the organisation's `policy` does not allow does not start (ADR-0168), and says why; one it allows does.
@Suite("A run the organisation does not allow does not start", .serialized)
struct ManagedPolicyTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-policy-run-\(UUID().uuidString)")

    private func source(_ policy: String, noSandbox: Bool = false) throws -> ConfigurationSource {
        let managed = root.appending(path: "managed").path
        try FileManager.default.createDirectory(atPath: managed, withIntermediateDirectories: true)
        try Data(#"{"policy": \#(policy)}"#.utf8).write(to: URL(filePath: managed + "/requirements.json"))
        let project = root.appending(path: "project").path
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        var flags = ConfigurationSource.Flags(model: "claude-test-1", provider: "anthropic")
        flags.noSandbox = noSandbox
        return ConfigurationSource(
            workingDirectory: project,
            flags: flags,
            environment: [
                "HOME": root.path, "XDG_CONFIG_HOME": root.appending(path: "config").path,
                "XDG_STATE_HOME": root.appending(path: "state").path, "ANTHROPIC_API_KEY": "test-key",
                "PATH": "/usr/bin:/bin"
            ],
            managed: ManagedFiles(directory: managed, owner: getuid())
        )
    }

    private func refusal(_ source: ConfigurationSource) async -> String? {
        do {
            _ = try await source.load(allowNetwork: false)
            return nil
        } catch {
            return "\(error)"
        }
    }

    @Test func `turning the sandbox off, or a model it does not list, is refused; what it allows runs`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let noSandbox = await refusal(try source(#"{"allowNoSandbox": false}"#, noSandbox: true))
        #expect(
            noSandbox?.hasPrefix("Your organisation does not allow turning the sandbox off") == true,
            "\(noSandbox ?? "ran")"
        )
        let model = await refusal(try source(#"{"models": ["gpt-*"]}"#))
        #expect(model?.contains("the model claude-test-1; it allows gpt-*") == true, "\(model ?? "ran")")
        #expect(await refusal(try source(#"{"models": ["claude-*"], "providers": ["anthropic"]}"#)) == nil)
        #expect(await refusal(try source(#"{"allowNoSandbox": false}"#)) == nil)
    }
}
