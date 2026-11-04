/// One conversion of an older session file, applied in memory when it opens (ADR-0144). The file is rewritten on its next change,
/// keeping the original as `.version-N`, as an upgrade always was. Steps run in order, each from the format it names, and each may run
/// again without changing anything. Every step is removed before 1.0.0-rc.1 (roadmap 0070); the format they leave is 1.0's baseline.
struct SessionMigration: Sendable {
    /// What it converts, in words.
    let name: String
    /// The format version of the files it converts.
    let from: Int
    /// The release before which it is removed; a test holds every step to it.
    let removeBefore: String
    /// The conversion of a recovered tree.
    let apply: @Sendable (inout SessionTree) -> Void

    /// Every step, oldest first.
    static let all: [SessionMigration] = [formatOne]

    /// Format 1 files differ only in their header: they are read as they are, and the rewrite writes format 2's.
    static let formatOne = SessionMigration(
        name: "format 1 to 2: the header names the version; the records are read as they are",
        from: 1,
        removeBefore: "1.0.0-rc.1",
        apply: { _ in }
    )

    /// Whether a file of format `version` opens: the current one, or one a step converts.
    static func opens(_ version: Int) -> Bool {
        version == SessionLog.formatVersion || all.contains { $0.from == version }
    }

    /// `tree`, read from a file of format `version`, converted by every step that applies to it.
    static func migrated(_ tree: SessionTree, from version: Int) -> SessionTree {
        var tree = tree
        for step in all where version <= step.from { step.apply(&tree) }
        return tree
    }
}
