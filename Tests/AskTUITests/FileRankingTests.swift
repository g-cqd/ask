import Testing

@testable import AskTUI

/// What the `@` picker lists for what was typed: a path that starts with it, then a file name that does, then a file name that contains
/// it, then a path that does; case ignored; listing order within a group; never more than `fileLimit`.
@Suite("The file picker ranks a path prefix above a file name above the rest of the path")
struct FileRankingTests {
    private let files = ProjectFiles(paths: [
        "Package.swift", "README.md", "docs/readme-notes.md", "docs/adr/0001-first.md", "Sources/ask/Ask.swift",
        "Sources/AskTUI/Transcript.swift", "Tests/AskTUITests/TranscriptTests.swift", "scripts/Read.sh"
    ])

    private func paths(_ query: String, in list: ProjectFiles? = nil) -> [String] {
        let list = list ?? files
        return PickerRanking.rank(files: list, query: query).indices.map { list.paths[$0] }
    }

    @Test func `an empty query lists the first files as they were listed`() {
        #expect(paths("") == files.paths)
    }

    @Test func `a path that starts with the query comes first, then a file name, then the rest`() {
        #expect(
            paths("read") == ["README.md", "docs/readme-notes.md", "scripts/Read.sh"],
            "a path prefix, then names, in listing order")
        #expect(
            paths("trans") == [
                "Sources/AskTUI/Transcript.swift", "Tests/AskTUITests/TranscriptTests.swift"
            ])
        #expect(paths("askt") == ["Sources/AskTUI/Transcript.swift", "Tests/AskTUITests/TranscriptTests.swift"])
    }

    @Test func `matching ignores case, and a query that matches nothing matches nothing`() {
        #expect(paths("README") == paths("readme"))
        #expect(paths("zzz").isEmpty)
        #expect(paths("a", in: ProjectFiles()).isEmpty)
    }

    @Test func `a slash in the query matches across directories`() {
        #expect(paths("docs/") == ["docs/readme-notes.md", "docs/adr/0001-first.md"])
        #expect(paths("ask/ask") == ["Sources/ask/Ask.swift"])
    }

    @Test func `a file name that starts with the query beats a directory that contains it`() {
        let list = ProjectFiles(paths: ["a/unit/x.swift", "b/unit.swift"])
        #expect(paths("unit", in: list) == ["b/unit.swift", "a/unit/x.swift"])
    }

    @Test func `a query found only in a directory of the path comes after every file name that holds it`() {
        let list = ProjectFiles(paths: ["x/adr/y.md", "my-adr.md", "adrift.md"])
        #expect(paths("adr", in: list) == ["adrift.md", "my-adr.md", "x/adr/y.md"])
    }

    @Test func `a query that only appears where two paths meet in the buffer matches neither`() {
        let list = ProjectFiles(paths: ["ab", "cd", "", "xyz", "ef"])
        #expect(paths("bc", in: list).isEmpty && paths("dxy", in: list).isEmpty && paths("zef", in: list).isEmpty)
        #expect(paths("cd", in: list) == ["cd"] && paths("b", in: list) == ["ab"])
    }

    @Test func `a path that holds the query twice is listed once, in the best group it earns`() {
        let list = ProjectFiles(paths: ["x/ab/ab.txt", "ab.txt/q", "other"])
        #expect(paths("ab", in: list) == ["ab.txt/q", "x/ab/ab.txt"])
    }

    @Test func `a hit after a boundary-crossing hit in the same buffer is still found`() {
        let list = ProjectFiles(paths: ["xa", "bb", "ab"])
        #expect(paths("ab", in: list) == ["ab"])
    }

    @Test func `a file name that starts with the query beats one that only contains it, whichever was listed first`() {
        let list = ProjectFiles(paths: ["a/xread.txt", "b/read.txt", "c/unread.txt"])
        #expect(paths("read", in: list) == ["b/read.txt", "a/xread.txt", "c/unread.txt"])
    }

    @Test func `a lower group that overflowed earlier does not stop the search before the best group is found`() {
        // 300 names contain the query, filling and overflowing their group, and only then do three paths that start with it appear.
        let list = ProjectFiles(paths: (0 ..< 300).map { "d/xab\($0).txt" } + (0 ..< 3).map { "abc\($0).txt" })
        let ranked = PickerRanking.rank(files: list, query: "ab")
        #expect(Array(ranked.indices.prefix(3).map { list.paths[$0] }) == ["abc0.txt", "abc1.txt", "abc2.txt"])
        #expect(ranked.indices.count == PickerRanking.fileLimit && ranked.capped)
    }

    @Test func `a full best group ends the search and says there were more`() {
        let list = ProjectFiles(paths: (0 ..< 300).map { "abc\($0).txt" } + ["abz.txt"])
        let ranked = PickerRanking.rank(files: list, query: "ab")
        #expect(ranked.indices == Array(0 ..< PickerRanking.fileLimit) && ranked.capped)
    }

    @Test func `no more than the limit are kept, and it says so`() {
        let many = ProjectFiles(paths: (0 ..< 500).map { "dir/file\($0).txt" })
        let ranked = PickerRanking.rank(files: many, query: "file")
        #expect(ranked.indices.count == PickerRanking.fileLimit && ranked.capped)
        #expect(ranked.indices == Array(0 ..< PickerRanking.fileLimit), "the first matches in listing order")
        let all = PickerRanking.rank(files: many, query: "")
        #expect(all.indices.count == PickerRanking.fileLimit && all.capped)
        #expect(!PickerRanking.rank(files: files, query: "read").capped)
    }

    @Test func `non-ASCII and wide names are matched by their lowercased form`() {
        let list = ProjectFiles(paths: ["docs/Ünïcode.md", "日本語/メモ.txt"])
        #expect(paths("ünï", in: list) == ["docs/Ünïcode.md"])
        #expect(paths("メモ", in: list) == ["日本語/メモ.txt"])
    }

    @Test func `where a name starts is where its last component starts, even for a path with no directory`() {
        let list = ProjectFiles(paths: ["a/b/c.txt", "plain.txt", "trailing/"])
        #expect(
            list.baseStarts.enumerated()
                .map { String(decoding: list.lowered[$0.element ..< list.starts[$0.offset + 1]], as: UTF8.self) } == [
                    "c.txt", "plain.txt", ""
                ])
    }
}
