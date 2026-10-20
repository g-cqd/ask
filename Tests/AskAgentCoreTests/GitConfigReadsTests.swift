import Testing

@testable import AskAgentCore

/// What git must read from the home directory: the files a global config includes and its excludes file. Git treats
/// an unreadable include as fatal, so a read allow-list without them breaks every commit.
@Suite("The files a git config names are found, however they are spelled")
struct GitConfigReadsTests {
    @Test func `include paths, quoted or not, conditional or not, with the home shorthand`() {
        let text = """
            [user]
            \tname = A
            \tpath = /not/an/include
            [include]
            \tpath = "/Users/a/Library/Mobile Documents/git/gitconfig"
            [includeIf "gitdir:~/work/"]
            \tpath = ~/work.gitconfig
            [core]
            \texcludesfile = ~/.gitignore_global
            \tpager = less
            """
        #expect(
            GitConfigReads.paths(in: text, directory: "/Users/a", home: "/Users/a") == [
                "/Users/a/Library/Mobile Documents/git/gitconfig", "/Users/a/work.gitconfig",
                "/Users/a/.gitignore_global"
            ])
    }

    @Test func `a relative include is relative to the file that includes it`() {
        #expect(
            GitConfigReads.paths(in: "[include]\n  path = shared/config", directory: "/Users/a/.config/git", home: "/h")
                == ["/Users/a/.config/git/shared/config"])
    }

    @Test func `keys and section names are case-insensitive, comments are ignored`() {
        let text = "# [include]\n[Include]\n PATH=/x # trailing\n[CORE]\n  excludesFile = /y\n; path = /z"
        #expect(GitConfigReads.paths(in: text, directory: "/", home: "/h") == ["/x", "/y"])
    }

    @Test func `nothing to find is nothing`() {
        #expect(GitConfigReads.paths(in: "", directory: "/", home: "/h").isEmpty)
        #expect(GitConfigReads.paths(in: "[include]\n", directory: "/", home: "/h").isEmpty)
    }
}
