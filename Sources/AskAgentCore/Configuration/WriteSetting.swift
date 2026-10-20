/// One configuration layer's write scope (roadmap 0042): everywhere, the project being worked on, or some paths.
/// Each layer that sets one narrows the ones below; see ``SandboxSection/writeScope(workspace:home:)``.
public enum WriteSetting: Sendable, Equatable, CustomStringConvertible {
    case anywhere
    /// The working directory ask was started in.
    case workspace
    /// These directories, absolute or starting with `~/`.
    case paths([String])

    public var description: String {
        switch self {
            case .anywhere: "anywhere"
            case .workspace: "workspace"
            case .paths(let paths): "[" + paths.joined(separator: ", ") + "]"
        }
    }

    /// Where this setting allows writing, for a run in `workspace` with the home directory `home`.
    func scope(workspace: String, home: String) -> PathScope {
        func canonical(_ path: String) -> String { CanonicalPath.of(path, relativeTo: "/") ?? path }
        switch self {
            case .anywhere: return .anywhere
            case .workspace: return .roots([canonical(workspace)])
            case .paths(let paths): return .roots(paths.map { canonical(SandboxSection.expand($0, home: home)) })
        }
    }
}
