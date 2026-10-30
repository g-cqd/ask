// @dl:accept -- each section validates its keys on its own; the key tables are the data
extension ConfigurationFile {
    /// The sandbox section's paths must be absolute or start with `~/`, and a project's file may not widen it.
    static func validateSandbox(
        _ section: SandboxSection?, path: String, isProject: Bool
    ) throws(ConfigurationError) {
        guard let section else { return }
        func paths(_ settings: [PathSetting]) -> [String] {
            settings.flatMap { setting -> [String] in
                if case .paths(let paths) = setting { return paths }
                return []
            }
        }
        for (key, entries) in [
            ("sandbox.readable", section.allowRead), ("sandbox.hide", section.denyRead),
            ("sandbox.write", paths(section.write)), ("sandbox.read", paths(section.read))
        ] {
            for entry in entries where !(entry.hasPrefix("/") || entry == "~" || entry.hasPrefix("~/")) {
                throw .outOfRange(
                    path: path, key: key, reason: "has \"\(entry)\": use an absolute path, or one starting with ~/")
            }
        }
        if isProject, !section.allowWrite.isEmpty {
            throw .outOfRange(
                path: path, key: "sandbox.writable",
                reason:
                    "can only be set in your own config file: a project that could open its own hooks would defeat it")
        }
        if isProject, !section.allowRead.isEmpty {
            throw .outOfRange(
                path: path, key: "sandbox.readable",
                reason:
                    "can only be set in your own config file: a project that could widen the sandbox would defeat it")
        }
    }
}
