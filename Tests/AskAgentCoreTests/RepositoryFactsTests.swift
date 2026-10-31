import Foundation
import Testing

@testable import AskAgentCore

/// What `modelScopes` matches a repository by (roadmap 0094), read from git's own files without starting git: within the cold-start
/// budget, and a folder without git is simply nothing to match.
@Suite("A repository's remotes and identity are read from git's files")
struct RepositoryFactsTests {
    private let root = URL(filePath: NSTemporaryDirectory()).appending(path: "ask-facts-\(UUID().uuidString)").path

    private func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func environment(home: String? = nil, xdg: String? = nil) -> [String: String] {
        var values = ["HOME": home ?? root + "/home"]
        if let xdg { values["XDG_CONFIG_HOME"] = xdg }
        return values
    }

    @Test func `remotes and the identity come from the repository's config, from a folder inside it`() throws {
        try write(
            """
            [core]
            \tbare = false
            [remote "origin"]
            \turl = git@github.com:acme/tool.git
            \tfetch = +refs/heads/*:refs/remotes/origin/*
            [remote "fork"]
            \turl = "https://github.com/me/tool"
            # a comment
            [user]
            \temail = jane@acme.com ; trailing comment
            \tname = Jane Doe
            """, to: root + "/repo/.git/config")
        try FileManager.default.createDirectory(atPath: root + "/repo/src/deep", withIntermediateDirectories: true)
        let facts = RepositoryFacts.read(project: root + "/repo/src/deep", environment: environment())
        #expect(facts.project == root + "/repo/src/deep")
        #expect(facts.home == root + "/home")
        #expect(facts.remotes == ["git@github.com:acme/tool.git", "https://github.com/me/tool"])
        #expect(facts.identities == ["jane@acme.com", "Jane Doe"])
    }

    @Test func `an identity the repository does not set comes from your git config, ~ first then XDG`() throws {
        try write("[remote \"origin\"]\n\turl = https://x/y\n", to: root + "/repo/.git/config")
        try write("[user]\n\tname = Global Name\n", to: root + "/home/.gitconfig")
        try write("[user]\n\temail = xdg@example.com\n\tname = XDG Name\n", to: root + "/xdg/git/config")
        let facts = RepositoryFacts.read(project: root + "/repo", environment: environment(xdg: root + "/xdg"))
        #expect(facts.identities == ["xdg@example.com", "Global Name"])
    }

    @Test func `an include, and an includeIf whose gitdir holds the repository, are followed where they stand`() throws
    {
        try write("[remote \"origin\"]\n\turl = https://x/y\n", to: root + "/home/work/app/.git/config")
        try write("[remote \"origin\"]\n\turl = https://x/z\n", to: root + "/home/play/app/.git/config")
        try write(
            """
            [user]
            \temail = me@home.example
            [include]
            \tpath = names.inc
            [includeIf "gitdir:~/work/"]
            \tpath = ~/work.inc
            """, to: root + "/home/.gitconfig")
        try write("[user]\n\tname = Included Name\n", to: root + "/home/names.inc")
        try write("[user]\n\temail = me@acme.com\n", to: root + "/home/work.inc")
        let work = RepositoryFacts.read(project: root + "/home/work/app", environment: environment())
        #expect(work.identities == ["me@acme.com", "Included Name"])
        let play = RepositoryFacts.read(project: root + "/home/play/app", environment: environment())
        #expect(play.identities == ["me@home.example", "Included Name"])
    }

    @Test func `a worktree's config is the main repository's`() throws {
        try write("[remote \"origin\"]\n\turl = https://example.com/main\n", to: root + "/main/.git/config")
        try write("../..\n", to: root + "/main/.git/worktrees/wt/commondir")
        try write("gitdir: \(root)/main/.git/worktrees/wt\n", to: root + "/wt/.git")
        let facts = RepositoryFacts.read(project: root + "/wt", environment: environment())
        #expect(facts.remotes == ["https://example.com/main"])
    }

    @Test func `a folder outside any repository has no remotes, and no identity without a git config`() throws {
        try FileManager.default.createDirectory(atPath: root + "/plain", withIntermediateDirectories: true)
        let facts = RepositoryFacts.read(project: root + "/plain", environment: environment())
        #expect(facts.remotes.isEmpty && facts.identities.isEmpty)
    }
}
