internal import Foundation

extension SandboxPolicy {
    /// ask's own protections, applied unless the user turns them off (ADR-0035).
    ///
    /// - **ask's configuration directory** cannot be read or written: it holds the credentials, the trust store and
    ///   the provider keys, and a model that could edit it could widen its own sandbox or trust its own project.
    /// - **ask's state directory** cannot be written: sessions are ask's record, and the model rewriting its own history
    ///   is not an edit it should be able to make. It can be read, since a cut command output is read back from there.
    /// - **Secret stores** a coding task has no need to read: `~/.aws`, `~/.gnupg`, keychains, `~/.netrc`, and ssh
    ///   *private keys*. Not `~/.ssh/config` or `known_hosts`, which `git` over ssh needs; the key itself is held by
    ///   the agent or read by `ssh`, which would then fail, so a key without an agent must be allowed explicitly.
    ///
    /// - Parameters:
    ///   - home: the user's home directory.
    ///   - configDirectory: ask's configuration directory.
    ///   - stateDirectory: ask's state directory, the one holding `sessions`.
    ///   - allowRead: paths the user has chosen to allow reading, which lift any default rule that is exactly one of
    ///     them. ask's own two directories are never lifted: a flag turns the sandbox off, a file cannot.
    ///   - denyRead: further directories the user wants kept unreadable, which only ever narrow.
    ///   - workspace: the run's workspace, whose git hooks and configuration are protected from writing; nil protects none.
    ///   - allowWrite: places protected from writing that the user has chosen to allow, which lift a rule that is exactly one of them.
    ///   - otherSecrets: more secret directories and files under the home, other agents' sign-ins, which the composition root names.
    /// - Returns: the policy. Every protection but ask's own two directories is askable: a call's request for it is put to the person.
    public static func standard(
        home: String, configDirectory: String, stateDirectory: String, allowRead: [String] = [],
        denyRead: [String] = [], workspace: String? = nil, allowWrite: [String] = [],
        otherSecrets: (directories: [String], files: [String]) = ([], [])
    ) -> SandboxPolicy {
        func canonical(_ path: String) -> String { CanonicalPath.of(path, relativeTo: "/") ?? path }
        func rules(_ base: String, _ subpaths: [String], _ literals: [String]) -> [SandboxRule] {
            subpaths.map { SandboxRule(canonical(base + "/" + $0), .subpath) }
                + literals.map { SandboxRule(canonical(base + "/" + $0), .literal) }
        }
        // An existing repository's hooks run at the person's next commit; a workspace with none yet can still be made one.
        func repositoryRules(_ workspace: String) -> [SandboxRule]? {
            FileManager.default.fileExists(atPath: workspace + "/.git")
                ? rules(workspace, [".git/hooks"], [".git/config"]) : nil
        }
        let readable = Set(allowRead.map { canonical($0).lowercased() })
        let writable = Set(allowWrite.map { canonical($0).lowercased() })
        let secrets = rules(
            home, StandardProtections.secretDirectories + otherSecrets.directories,
            StandardProtections.secretFiles + otherSecrets.files
        )
        .filter { !readable.contains($0.path.lowercased()) }
        let runsLater =
            (rules(home, StandardProtections.runningDirectories, StandardProtections.runningFiles)
            + rules("", StandardProtections.systemRunningDirectories, [])
            + (workspace.flatMap(repositoryRules) ?? []))
            .filter { !writable.contains($0.path.lowercased()) }
        return SandboxPolicy(
            denyRead: [SandboxRule(canonical(configDirectory), .subpath)] + secrets
                + denyRead.map { SandboxRule(canonical($0), .subpath) },
            denyWrite: [SandboxRule(canonical(stateDirectory), .subpath)] + runsLater, askable: secrets + runsLater)
    }
}
