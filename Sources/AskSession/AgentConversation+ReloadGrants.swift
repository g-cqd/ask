internal import Foundation

extension AgentConversation {
    /// A new name for the grants a reload carries: in the `reload` folder of ask's configuration, private to the person, which the
    /// sandbox keeps every command and file tool from (security audit 2026-11-22, HIGH-10). `$TMPDIR` was writable by a command.
    static func reloadGrantsPath(configDirectory: String) -> String {
        let folder = configDirectory + "/reload"
        // try?: without the folder the grants are not written, and the new build asks again for what was allowed
        try? FileManager.default.createDirectory(
            atPath: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return folder + "/grants-" + UUID().uuidString + ".json"
    }
}
