extension SandboxRequest {
    /// `policy` widened to what this request asked for, once the user has granted it: the network level and the write
    /// and read roots it named replace the run's. The protections stay.
    public func granted(over policy: SandboxPolicy, workingDirectory: String) -> SandboxPolicy {
        var widened = policy
        if let network { widened.network = network }
        if let write { widened.write = .roots(Self.canonical(write, workingDirectory)) }
        if let read { widened.read = .roots(Self.canonical(read, workingDirectory)) }
        return widened
    }

    /// Whether `grants`, requests the user allowed for the session, contain this one: every dimension it names is
    /// within some grant's. A grant for writing is not one for reading.
    public func isCovered(by grants: [SandboxRequest], workingDirectory: String) -> Bool {
        guard !grants.isEmpty else { return false }
        if let network, !grants.contains(where: { ($0.network ?? .none) >= network }) { return false }
        for (asked, granted) in [(write, grants.compactMap(\.write)), (read, grants.compactMap(\.read))] {
            guard let asked else { continue }
            let roots = granted.flatMap { Self.canonical($0, workingDirectory) }
            for path in Self.canonical(asked, workingDirectory)
            where !roots.contains(where: { SandboxRule($0, .subpath).matches(path) }) {
                return false
            }
        }
        return true
    }

    private static func canonical(_ paths: [String], _ workingDirectory: String) -> [String] {
        paths.map { CanonicalPath.of($0, relativeTo: workingDirectory) ?? $0 }
    }
}
