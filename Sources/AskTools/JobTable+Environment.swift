internal import AskAgentCore
internal import Foundation

extension JobTable {
    /// Creates a private `0700` scratch directory for sandboxed commands (`TMPDIR`, MED-07).
    static func makePrivateTempDirectory() -> String? {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "ask-tmp-\(getpid())-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(
                at: scratch,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return scratch.path
        } catch {
            return nil
        }
    }

    /// What a command in `context` is given of ask's environment: the policy's filter, a private `0700` `TMPDIR`
    /// when sandboxed (MED-07), and under the `provider` network level the proxy's address, so its traffic goes where
    /// the sandbox lets it (roadmap 0021).
    func commandEnvironment(for context: ToolContext) -> [String: String] {
        var values = context.commandEnvironment.filtered(environment)
        if !context.sandbox.isUnrestricted, let privateTempDirectory {
            values["TMPDIR"] = privateTempDirectory
        }
        if context.sandbox.network == .provider {
            values.merge(ProviderAccess.commandEnvironment()) { _, proxy in proxy }
        }
        return values
    }
}
