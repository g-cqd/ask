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
    /// - Returns: the policy.
    public static func standard(
        home: String, configDirectory: String, stateDirectory: String, allowRead: [String] = [],
        denyRead: [String] = []
    ) -> SandboxPolicy {
        func canonical(_ path: String) -> String { CanonicalPath.of(path, relativeTo: "/") ?? path }
        let allowed = Set(allowRead.map { canonical($0).lowercased() })
        let secrets: [SandboxRule] =
            [".aws", ".gnupg", "Library/Keychains"].map { SandboxRule(canonical(home + "/" + $0), .subpath) }
            + [".netrc"].map { SandboxRule(canonical(home + "/" + $0), .literal) }
            + ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "id_ecdsa_sk", "id_ed25519_sk"]
            .map { SandboxRule(canonical(home + "/.ssh/" + $0), .literal) }
        let kept = secrets.filter { !allowed.contains($0.path.lowercased()) }
        return SandboxPolicy(
            denyRead: [SandboxRule(canonical(configDirectory), .subpath)] + kept
                + denyRead.map { SandboxRule(canonical($0), .subpath) },
            denyWrite: [SandboxRule(canonical(stateDirectory), .subpath)])
    }
}
