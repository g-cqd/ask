/// The git commands ask runs by itself (the status bar's segment, the forge's repository and branch), before the person approved
/// anything, in a folder whose `.git` may not be theirs. A repository's own configuration can make git run a command: its file-system
/// monitor (`core.fsmonitor`) on any read of the index, and a `filter` that `.gitattributes` names when a file's content is compared
/// (security audit 3, 2026-11-13: both ran on `git status`). So every query here:
///
/// - turns the monitor off (`-c core.fsmonitor=false`);
/// - reads attributes from the empty tree (`--attr-source`), so no file has a filter;
/// - takes no lock (`GIT_OPTIONAL_LOCKS=0`), never standing in the way of a git command the model or the person runs;
/// - has two seconds.
///
/// A git too old to know `--attr-source` (before 2.41), or a repository whose object format has another empty tree, answers
/// nothing: no segment, never an unguarded run. What the model runs through `bash` is not this: it is approved and sandboxed.
enum GitQuery {
    /// The empty tree of a SHA-1 repository: in every one, written or not.
    static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// What `git ARGUMENTS` prints in `directory`, or nil when there is no git, it failed, or it took too long.
    static func output(_ arguments: [String], in directory: String, path: String?) async -> String? {
        guard let git = CommandCheck.executable("git", path: path) else { return nil }
        var environment = CommandCheck.environment(path: path)
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        let outcome = await CommandCheck.run(
            git,
            ["-C", directory, "-c", "core.fsmonitor=false", "--attr-source=" + emptyTree] + arguments,
            environment: environment,
            deadline: .seconds(2)
        )
        guard case .ran(let ran) = outcome, ran.status == 0 else { return nil }
        return ran.output
    }
}
