import Darwin
import Foundation
import Testing

@testable import AskAgentCore

/// `policy.managedHooksOnly` (roadmap 0130): only the organisation's documents may set a hook command. One the person set is replaced
/// by the organisation's, or off when they set none, and said; without the policy, the person's stands.
@Suite("Only the organisation's hooks", .serialized)
struct ManagedHooksPolicyTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-hooks-\(UUID().uuidString)").path

    private func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: URL(filePath: path))
    }

    private func load() throws -> ConfigurationLoader.Result {
        try ConfigurationLoader(
            project: root + "/project",
            configDirectory: root + "/config",
            environment: [:],
            managed: ManagedFiles(directory: root + "/managed", owner: getuid())
        )
        .load()
    }

    @Test
    func `the person's hook is off under the policy, the organisation's stands, and without it the person's does`()
        throws
    {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/config/config.json", #"{"hooks":{"check":"mine.sh","maxContinues":5}}"#)
        #expect(try load().configuration.hooks.value.check == "mine.sh", "no policy: the person's hook")
        try write(root + "/managed/requirements.json", #"{"policy":{"managedHooksOnly":true}}"#)
        var loaded = try load()
        #expect(loaded.configuration.hooks.value.check == nil)
        #expect(loaded.configuration.hooks.value.maxContinues == 5, "only the command is the organisation's to set")
        #expect(
            loaded.notices.contains { $0.contains("hooks.check") && $0.hasSuffix("it is off.") },
            "\(loaded.notices)"
        )
        try write(root + "/managed/defaults.json", #"{"hooks":{"check":"theirs-default.sh"}}"#)
        try write(root + "/managed/defaults.d/2-later.json", #"{"hooks":{"check":"theirs-later.sh"}}"#)
        loaded = try load()
        #expect(
            loaded.configuration.hooks.value.check == "theirs-later.sh",
            "the later of their defaults, over the person's"
        )
        #expect(loaded.notices.contains { $0.hasSuffix("the organisation's runs instead.") })
        try write(
            root + "/managed/requirements.json",
            #"{"policy":{"managedHooksOnly":true},"hooks":{"check":"required.sh"}}"#
        )
        loaded = try load()
        #expect(loaded.configuration.hooks.value.check == "required.sh")
        try FileManager.default.removeItem(atPath: root + "/config/config.json")
        loaded = try load()
        #expect(
            loaded.configuration.hooks.value.check == "required.sh"
                && !loaded.notices.contains { $0.contains("hooks.check") }
        )
    }
}
