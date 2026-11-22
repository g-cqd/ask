internal import AskAgentCore
internal import Foundation
internal import Testing

@testable import AskSession

/// The grants a reload carries are kept where no command or file tool may read or write them (security audit 2026-11-22, HIGH-10).
@Suite("A reload's grants are kept from the sandbox")
struct ReloadGrantsPathTests {
    @Test func `the file is in ask's configuration, in a folder private to the person, which the sandbox denies`()
        throws
    {
        let home = FileManager.default.temporaryDirectory.appending(path: "ask-reload-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let config = home + "/.config/ask"
        let path = AgentConversation.reloadGrantsPath(configDirectory: config)
        #expect(
            path.hasPrefix(config + "/reload/grants-")
                && path != AgentConversation.reloadGrantsPath(configDirectory: config)
        )
        let mode = try FileManager.default.attributesOfItem(atPath: config + "/reload")[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o700)
        let policy = SandboxPolicy.standard(
            home: home,
            configDirectory: config,
            stateDirectory: home + "/.local/state/ask"
        )
        #expect(!policy.authorize(.read, path: path, relativeTo: home).isAllowed)
        #expect(!policy.authorize(.write, path: path, relativeTo: home).isAllowed)
        #expect(
            policy.authorize(.write, path: NSTemporaryDirectory() + "x.json", relativeTo: home).isAllowed,
            "where it was before"
        )
    }
}
