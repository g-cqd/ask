internal import Foundation

/// What `modelScopes` matches a project by (roadmap 0094): its folder, its remotes and the git identity it commits as.
///
/// Read from git's files rather than by starting git, which would cost the cold-start budget; a folder outside a repository has no
/// remotes, and an identity no config sets is absent.
public struct RepositoryFacts: Sendable, Equatable {
    /// The project's folder, absolute.
    public var project: String
    /// The home folder, what `~` in a path pattern means.
    public var home: String
    /// Every remote's URL, in the order the config lists them.
    public var remotes: [String]
    /// `user.email`, then `user.name`, each where git would take it from.
    public var identities: [String]

    public init(project: String, home: String, remotes: [String], identities: [String]) {
        self.project = project
        self.home = home
        self.remotes = remotes
        self.identities = identities
    }

    /// The facts of the repository holding `project`, with `HOME` and `XDG_CONFIG_HOME` from `environment`.
    public static func read(project: String, environment: [String: String]) -> RepositoryFacts {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let repository = gitDirectory(above: project)
        let context = GitConfigFile.Context(gitDirectory: repository?.own, home: home)
        let xdg =
            (environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config") + "/git/config"
        // Git reads the XDG file, then ~/.gitconfig, then the repository's, each over the one before.
        var merged = GitConfigFile.read(xdg, context: context)
        merged.merge(GitConfigFile.read(home + "/.gitconfig", context: context))
        let local = repository.map { GitConfigFile.read($0.shared + "/config", context: context) } ?? GitConfigFile()
        merged.merge(local)
        return RepositoryFacts(
            project: project, home: home, remotes: local.remotes,
            identities: [merged.email, merged.name].compactMap { $0 })
    }

    /// The git directory of the repository `folder` is in, and the one it shares its config with: the same `.git` folder, or for
    /// a worktree (a `.git` file naming its git directory) the main repository's, from `commondir`.
    private static func gitDirectory(above folder: String) -> (own: String, shared: String)? {
        var current = folder
        while true {
            let dotGit = current + "/.git"
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isFolder) {
                return isFolder.boolValue ? (dotGit, dotGit) : linked(dotGit, in: current)
            }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current, !parent.isEmpty else { return nil }
            current = parent
        }
    }

    /// Where a `.git` file leads: `gitdir: X`, then `X/commondir` when X is a worktree's.
    private static func linked(_ file: String, in folder: String) -> (own: String, shared: String)? {
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("gitdir:") else { return nil }
        var own = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !own.hasPrefix("/") { own = folder + "/" + own }
        own = (own as NSString).standardizingPath
        guard let common = FileManager.default.contents(atPath: own + "/commondir") else { return (own, own) }
        let relative = String(decoding: common, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let shared = relative.hasPrefix("/") ? relative : own + "/" + relative
        return (own, (shared as NSString).standardizingPath)
    }
}
